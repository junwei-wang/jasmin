(* * Intermediate language IL *)

(* ** Imports and abbreviations *)
open Core_kernel.Std
open Arith

module F = Format
module P = ParserUtil
module L = ParserUtil.Lexing

(* ** Names
 * ------------------------------------------------------------------------ *)
(* *** Summary
We use different types for the different namespaces for:
- function names
- parameters: global / module-level variables
- variables: function local variables
*)
(* *** Code *)

module Name = struct
  module T : sig
    type t [@@deriving compare,sexp]
    val hash : t -> int
    val pp : F.formatter -> t -> unit
    val mk : string -> t
    val to_string : t -> string
  end = struct
    type t = string [@@deriving compare,sexp]
    let hash v = Hashtbl.hash v
    let pp fmt (n : t) = Util.pp_string fmt n
    let mk (s : string) = s
    let to_string (n : t) = n
  end
  include T
  include Comparable.Make(T)
  include Hashable.Make(T)
end

module type NAME = sig
  include module type of Name
end

module Pname : NAME = Name
module Fname : NAME = Name
module Vname : NAME = Name

(* ** Compile time expressions
 * ------------------------------------------------------------------------ *)
(* *** Summary
Programs in our language are parameterized by parameter variables.
For a mapping from parameter variables to u64 values, the program
can be partially evaluated and the following constructs can be eliminated:
- for loops 'for i in lb..ub { ... }' can be unfolded
- if-then-else 'if ce { i1 } else { i2 }' can be replaced by i1/i2 after
  evaluating 'ce'
- indexes: array accesses 'r[e]' indexed with expressions 'e' over parameters
  can be indexed by u64 values
*)
(* *** Code *)

type pop_u64 =
  | Pplus
  | Pmult
  | Pminus
  [@@deriving compare,sexp]

type 'a pexpr_g =
  | Patom of 'a
  | Pbinop of pop_u64 * 'a pexpr_g * 'a pexpr_g
  | Pconst of u64
  [@@deriving compare,sexp]


module Param = struct
  module T = struct
    type dexpr = t pexpr_g [@@deriving compare,sexp]
 
    and ty =
      | Bool
      | U64
      | Arr of dexpr
      | TInvalid
      [@@deriving compare,sexp]

    and t = {
      name : Pname.t; (* FIXME: do we need a number? *)
      ty   : ty;
      loc  : L.loc;
    } [@@deriving compare,sexp]

    let hash = Hashtbl.hash
  end
  include T
  include Comparable.Make(T)
  include Hashable.Make(T)
  let pp fmt (p : t) = Pname.pp fmt p.name
end

include Param.T

(* ** Types, variables, and parameters
 * ------------------------------------------------------------------------ *)

type stor =
  | Inline
  | Stack
  | Reg
  | SInvalid (* invalid value used for initialization *)
  [@@deriving compare,sexp]

module Var = struct
  module T = struct
    type t = {
      name : Vname.t;
      num  : int;
      stor : stor;
      ty   : ty;
      loc  : L.loc;
    } [@@deriving compare,sexp]

    let hash = Hashtbl.hash
  end
  include T
  include Comparable.Make(T)
  include Hashable.Make(T)
  let pp fmt (v : t) =
    if Int.(v.num = 0) then
      Vname.pp fmt v.name
    else
      F.fprintf fmt "%a.%i" Vname.pp v.name v.num
end

(* ** Atom, compile-time expressions, and conditions
 * ------------------------------------------------------------------------ *)

type patom =
  | Pparam of Param.t
  | Pvar   of Var.t
  [@@deriving compare,sexp]

type pexpr = patom pexpr_g
  [@@deriving compare,sexp]

type pop_bool =
  | Peq
  | Pineq
  | Pless
  | Pleq
  | Pgreater
  | Pgeq
  [@@deriving compare,sexp]

type pcond =
  | Ptrue
  | Pnot of pcond
  | Pand of pcond * pcond
  | Pcmp of pop_bool * pexpr * pexpr
  [@@deriving compare,sexp]

(* ** Types, sources, and destinations
 * ------------------------------------------------------------------------ *)
(* *** Summary
We define:
- pseudo-registers that hold values and addresses
- sources (r-values)
- destinations (l-values)
*)
(* *** Code *)

type idx =
  | Iconst of pexpr
  | Ivar   of Var.t
  [@@deriving compare,sexp]

type dest = {
  d_var : Var.t;
  d_idx : idx option;
  d_loc : L.loc
} [@@deriving compare,sexp]

type src =
  | Imm of pexpr (* Simm(i): immediate value i            *)
  | Src of dest  (* Sreg(d): where d destination register *)
  [@@deriving compare,sexp]

(* ** Operators and constructs for intermediate language
 * ------------------------------------------------------------------------ *)
(* *** Summary
The language supports the fixed operations given in 'op' (and function calls).
*)
(* *** Code *)

type dir      = Left   | Right                [@@deriving compare,sexp]
type carry_op = O_Add  | O_Sub                [@@deriving compare,sexp]
type three_op = O_Imul | O_And | O_Xor | O_Or [@@deriving compare,sexp]

 type op =
  | ThreeOp of three_op
  | Umul
  | Carry   of carry_op
  | Cmov    of bool (* negate flag *)
  | Shift   of dir
  [@@deriving compare,sexp]

(* ** Base instructions, instructions, and statements
 * ------------------------------------------------------------------------ *)
(* *** Summary
- base instructions (assignment, operation, call, comment)
- instructions (base instructions, if, for)
- statements (list of instructions) *)
(* *** Code *)

type fcond = { fc_neg : bool; fc_var : Var.t }
  [@@deriving compare,sexp]

type fcond_or_pcond =
  | Fcond of fcond (* flag condition *)
  | Pcond of pcond (* parametric condition *)
  [@@deriving compare,sexp]

type while_type =
  | WhileDo (* while t { ... } *)
  | DoWhile (* do { ... } while t; *)
  [@@deriving compare,sexp]

type assgn_type =
  | Mv (* compile to move *)
  | Eq (* use as equality constraint in reg-alloc and compile to no-op *)
  [@@deriving compare,sexp]

type if_type =
  | Run   (* compile to move *)
  | Macro (* use as equality constraint in reg-alloc and compile to no-op *)
  [@@deriving compare,sexp]

type base_instr =
  
  | Assgn of dest * src * assgn_type
    (* Assgn(d,s): d = s *)

  | Op of op * dest list * src list
    (* Op(ds,o,ss): ds = o(ss) *)

  | Call of Fname.t * dest list * src list
    (* Call(fname,rets,args): rets = fname(args) *)

  | Load of dest * src * pexpr
    (* Load(d,src,pe): d = MEM[src + pe] *)

  | Store of src * pexpr * src
    (* Store(src1,pe,src2): MEM[src1 + pe] = src2 *) 

  | Comment of string
    (* Comment(s): /* s */ *)

  [@@deriving compare,sexp]

type 'info instr =

  | Block of (base_instr L.located) list * 'info option

  | If of fcond_or_pcond * 'info stmt * 'info stmt * 'info option
    (* If(c1,s1,s2): if c1 { s1 } else s2 *)

  | For of dest * pexpr * pexpr * 'info stmt * 'info option
    (* For(v,lower,upper,s): for v in lower..upper { s } *)

  | While of while_type * fcond * 'info stmt * 'info option
    (* While(wt,fcond,s):
         wt=WhileDo  while fcond { s }
         wt=DoWhile  do          { s } while fcond; *)

and 'info stmt = (('info instr) L.located) list
  [@@deriving compare,sexp]

(* ** Function definitions, declarations, and modules
 * ------------------------------------------------------------------------ *)

type call_conv =
  | Extern
  | Custom
  [@@deriving compare,sexp]

type tinfo = (stor * ty) [@@deriving compare,sexp]

type 'info fundef = {
  f_body      : 'info stmt; (* function body *)
  f_arg       : Var.t list; (* argument values *)
  f_ret       : Var.t list; (* return values *)
  f_call_conv : call_conv;  (* callable or internal function *)
} [@@deriving compare,sexp]

type foreigndef = {
  fo_py_def : string option;
  fo_arg_ty : tinfo list;
  fo_ret_ty : tinfo list
} [@@deriving compare,sexp]

type 'info func =
  | Native  of 'info fundef
  | Foreign of foreigndef
  [@@deriving compare,sexp]

type 'info modul = {
  m_params : Param.t list;           (* module parameters           *)
  m_funcs  : 'info func Fname.Map.t; (* map from names to functions *)
} [@@deriving compare,sexp]

(* ** Values
 * ------------------------------------------------------------------------ *)

type value =
  | Vu64 of u64
  | Varr of u64 U64.Map.t
  [@@deriving compare,sexp]

(* ** Define Map, Hashtables, and Sets
 * ------------------------------------------------------------------------ *)

module Dest = struct
  module T = struct
    type t = dest [@@deriving compare,sexp]
    let compare = compare_t
    let hash v = Hashtbl.hash v
  end
  include T
  include Comparable.Make(T)
  include Hashable.Make(T)
end
