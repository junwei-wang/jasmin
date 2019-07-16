(* -------------------------------------------------------------------- *)
open Utils
open Bigint.Notations

(* -------------------------------------------------------------------- *)
module LM = Type

(* -------------------------------------------------------------------- *)
type rsize = [ `U8 | `U16 | `U32 | `U64 ]

(* -------------------------------------------------------------------- *)
let rs_of_ws =
  function
  | LM.U8 -> `U8
  | LM.U16 -> `U16
  | LM.U32 -> `U32
  | LM.U64 -> `U64
  | _ -> assert false

let rs_of_ve =
  function
  | LM.VE8 -> `U8
  | LM.VE16 -> `U16
  | LM.VE32 -> `U32
  | LM.VE64 -> `U64

(* -------------------------------------------------------------------- *)
exception InvalidRegSize of LM.wsize

(* -------------------------------------------------------------------- *)
let mangle (x : string) = "_" ^ x

(* -------------------------------------------------------------------- *)
let iwidth = 4

let pp_gen (fmt : Format.formatter) = function
  | `Label lbl ->
      Format.fprintf fmt "%s:" lbl
  | `Instr (s, []) ->
      Format.fprintf fmt "\t%-.*s" iwidth s
  | `Instr (s, args) ->
      Format.fprintf fmt "\t%-.*s\t%s"
        iwidth s (String.join ", " args)

let pp_gens (fmt : Format.formatter) xs =
  List.iter (Format.fprintf fmt "%a\n%!" pp_gen) xs

(* -------------------------------------------------------------------- *)
let string_of_label name (p : Linear.label) =
  Format.sprintf "L%s$%d" name (Conv.int_of_pos p)

(* -------------------------------------------------------------------- *)
let string_of_funname tbl (p : Expr.funname) : string =
  (Conv.fun_of_cfun tbl p).fn_name

(* -------------------------------------------------------------------- *)
type lreg =
  | RNumeric of int
  | RAlpha   of char
  | RSpecial of [`RStack | `RBase | `RSrcIdx | `RDstIdx]

let lreg_of_reg (reg : X86_sem.register) =
  match reg with
  | RSP -> RSpecial `RStack
  | RBP -> RSpecial `RBase
  | RSI -> RSpecial `RSrcIdx
  | RDI -> RSpecial `RDstIdx
  | RAX -> RAlpha 'a'
  | RBX -> RAlpha 'b'
  | RCX -> RAlpha 'c'
  | RDX -> RAlpha 'd'
  | R8  -> RNumeric  8
  | R9  -> RNumeric  9
  | R10 -> RNumeric 10
  | R11 -> RNumeric 11
  | R12 -> RNumeric 12
  | R13 -> RNumeric 13
  | R14 -> RNumeric 14
  | R15 -> RNumeric 15

(* -------------------------------------------------------------------- *)
let rsize_of_wsize (ws : LM.wsize) =
  match ws with
  | U8  -> `U8
  | U16 -> `U16
  | U32 -> `U32
  | U64 -> `U64
  | _   -> raise (InvalidRegSize ws)

(* -------------------------------------------------------------------- *)
let pp_instr_rsize (rs : rsize) =
  match rs with
  | `U8  -> "b"
  | `U16 -> "w"
  | `U32 -> "l"
  | `U64 -> "q"

(* -------------------------------------------------------------------- *)
let pp_register (ws : rsize) (reg : X86_sem.register) =
  let ssp = function
    | `RStack  -> "sp"
    | `RBase   -> "bp"
    | `RSrcIdx -> "si"
    | `RDstIdx -> "di" in

  match lreg_of_reg reg, ws with
  | RNumeric i, `U8  -> Printf.sprintf "r%d%s" i "b"
  | RNumeric i, `U16 -> Printf.sprintf "r%d%s" i "w"
  | RNumeric i, `U32 -> Printf.sprintf "r%d%s" i "d"
  | RNumeric i, `U64 -> Printf.sprintf "r%d%s" i ""
  | RAlpha c  , `U8  -> Printf.sprintf "%s%c%s" ""  c "l"
  | RAlpha c  , `U16 -> Printf.sprintf "%s%c%s" ""  c "x"
  | RAlpha c  , `U32 -> Printf.sprintf "%s%c%s" "e" c "x"
  | RAlpha c  , `U64 -> Printf.sprintf "%s%c%s" "r" c "x"
  | RSpecial x, `U8  -> Printf.sprintf "%s%s%s" ""  (ssp x) "l"
  | RSpecial x, `U16 -> Printf.sprintf "%s%s%s" ""  (ssp x) ""
  | RSpecial x, `U32 -> Printf.sprintf "%s%s%s" "e" (ssp x) ""
  | RSpecial x, `U64 -> Printf.sprintf "%s%s%s" "r" (ssp x) ""

(* -------------------------------------------------------------------- *)
let pp_register ?(prefix = "%") (ws : rsize) (reg : X86_sem.register) =
  Printf.sprintf "%s%s" prefix (pp_register ws reg)

(* -------------------------------------------------------------------- *)
let pp_scale (scale : X86_sem.scale) =
  match scale with
  | Scale1 -> "1"
  | Scale2 -> "2"
  | Scale4 -> "4"
  | Scale8 -> "8"

(* -------------------------------------------------------------------- *)
let pp_address (addr : X86_sem.address) =
  let disp = Conv.bi_of_int64 addr.ad_disp in
  let base = addr.ad_base in
  let off  = addr.ad_offset in
  let scal = addr.ad_scale in

  if Option.is_none base && Option.is_none off then
    Bigint.to_string disp
  else begin
    let disp = if disp =^ Bigint.zero then None else Some disp in
    let disp = odfl "" (omap Bigint.to_string disp) in
    let base = odfl "" (omap (pp_register `U64) base) in
    let off  = omap (pp_register `U64) off in

    match off, scal with
    | None, _ ->
        Printf.sprintf "%s(%s)" disp base
    | Some off, Scale1 ->
        Printf.sprintf "%s(%s,%s)" disp base off
    | Some off, _ ->
        Printf.sprintf "%s(%s,%s,%s)" disp base off (pp_scale scal)
  end

(* -------------------------------------------------------------------- *)
let pp_imm (imm : Bigint.zint) =
  Format.sprintf "$%s" (Bigint.to_string imm)

(* -------------------------------------------------------------------- *)
let pp_label = string_of_label

(* -------------------------------------------------------------------- *)
let pp_global (g: Expr.global) =
  Format.sprintf "%s(%%rip)" (Conv.global_of_cglobal g |> snd)

(* -------------------------------------------------------------------- *)
let pp_opr (ws : rsize) (op : X86_sem.oprd) =
  match op with
  | Imm_op imm ->
      pp_imm (Conv.bi_of_int64 imm)

  | Glo_op g ->
      pp_global g

  | Reg_op reg ->
      pp_register ws reg

  | Adr_op addr ->
      pp_address addr

(* -------------------------------------------------------------------- *)
let pp_imr (ws : rsize) (op : X86_sem.ireg) =
  match op with
  | Imm_ir imm ->
      pp_imm (Conv.bi_of_int64 imm)

  | Reg_ir reg ->
      pp_register ws reg

(* -------------------------------------------------------------------- *)
let pp_ct (ct : X86_sem.condt) =
  match ct with
  | O_ct   -> "o"
  | NO_ct  -> "no"
  | B_ct   -> "b"
  | NB_ct  -> "nb"
  | E_ct   -> "e"
  | NE_ct  -> "ne"
  | BE_ct  -> "be"
  | NBE_ct -> "nbe"
  | S_ct   -> "s"
  | NS_ct  -> "ns"
  | P_ct   -> "p"
  | NP_ct  -> "np"
  | L_ct   -> "l"
  | NL_ct  -> "nl"
  | LE_ct  -> "le"
  | NLE_ct -> "nle"

(* -------------------------------------------------------------------- *)
let pp_xmm_register (ws: LM.wsize) (r: X86_sem.xmm_register) : string =
  Format.sprintf "%%%smm%d"
    (match ws with
     | U128 -> "x"
     | U256 -> "y"
     | _ -> assert false)
    (match r with
     | XMM0 -> 0
     | XMM1 -> 1
     | XMM2 -> 2
     | XMM3 -> 3
     | XMM4 -> 4
     | XMM5 -> 5
     | XMM6 -> 6
     | XMM7 -> 7
     | XMM8 -> 8
     | XMM9 -> 9
     | XMM10 -> 10
     | XMM11 -> 11
     | XMM12 -> 12
     | XMM13 -> 13
     | XMM14 -> 14
     | XMM15 -> 15)

(* -------------------------------------------------------------------- *)
let pp_rm128 (ws: LM.wsize) : X86_sem.rm128 -> string =
  function
  | RM128_reg r -> pp_xmm_register ws r
  | RM128_mem a -> pp_address a
  | RM128_glo g -> pp_global g

let pp_m128 : X86_sem.m128 -> string =
  function
  | M128_mem a -> pp_address a
  | M128_glo g -> pp_global g
(* -------------------------------------------------------------------- *)
let pp_iname (rs : rsize) (name : string) =
  Printf.sprintf "%s%s" name (pp_instr_rsize rs)

let pp_iname2 (rs1 : rsize) (rs2: rsize) (name : string) =
  Printf.sprintf "%s%s%s" name (pp_instr_rsize rs1) (pp_instr_rsize rs2)

(* -------------------------------------------------------------------- *)
let pp_instr_velem =
  function
  | LM.VE8 -> "b"
  | LM.VE16 -> "w"
  | LM.VE32 -> "d"
  | LM.VE64 -> "q"

let pp_instr_velem_long =
  function
  | LM.VE8 -> "bw"
  | LM.VE16 -> "wd"
  | LM.VE32 -> "dq"
  | LM.VE64 -> "qdq"

let pp_viname ?(long = false) (ve: LM.velem) (name: string) =
  Printf.sprintf "%s%s" name ((if long then pp_instr_velem_long else pp_instr_velem) ve)

(* -------------------------------------------------------------------- *)
let pp_instr_unop name ws op =
  let rs = rs_of_ws ws in
  `Instr (pp_iname rs name, [pp_opr rs op])

let pp_instr_binop name ws op1 op2 =
  let rs = rs_of_ws ws in
  `Instr (pp_iname rs name, [pp_opr rs op2; pp_opr rs op1])

let pp_sh_d name ws op1 op2 ir =
  let rs = rs_of_ws ws in
  `Instr (pp_iname rs name, [pp_imr `U8 ir; pp_register rs op2; pp_opr rs op1])

let pp_instr_rro name ws dst src1 src2 =
  let rs = rs_of_ws ws in
  `Instr (pp_iname rs name, [pp_opr rs src2; pp_register rs src1; pp_register rs dst])

(* -------------------------------------------------------------------- *)
let pp_movx name wsd wss dst src =
  let rsd = rs_of_ws wsd in
  let rss = rs_of_ws wss in
  `Instr (pp_iname2 rss rsd name, [pp_opr rss src; pp_register rsd dst])

(* -------------------------------------------------------------------- *)
let pp_rm128_binop name sz dst src1 src2 =
    `Instr (name, [pp_rm128 sz src2; pp_rm128 sz src1; pp_rm128 sz dst])

let pp_xmm_binop name sz dst src1 src2 =
  `Instr (name, [pp_rm128 sz src2 ; pp_xmm_register sz src1 ; pp_xmm_register sz dst ])

let pp_vpsxldq d sz dst src i =
  `Instr ("vps" ^ d ^ "ldq", [ pp_imm (Conv.bi_of_int8 i); pp_xmm_register sz src; pp_xmm_register sz dst ])

let pp_vpshuf suf sz dst src1 src2 =
  `Instr ("vpshuf" ^ suf, [pp_imm (Conv.bi_of_int8 src2); pp_rm128 sz src1; pp_xmm_register sz dst])

let pp_vpunpck suf ve sz dst src1 src2 =
  `Instr (pp_viname ~long:true ve ("vpunpck" ^ suf), [ pp_rm128 sz src2 ; pp_xmm_register sz src1 ; pp_xmm_register sz dst ])

let pp_xxri name sz dst src1 src2 mask =
    `Instr(name, [pp_imm (Conv.bi_of_int8 mask); pp_rm128 sz src2; pp_xmm_register sz src1; pp_xmm_register sz dst])

(* -------------------------------------------------------------------- *)
let pp_instr name (i : X86_sem.asm) =
  match i with
  | ALIGN ->
    `Instr (".p2align", ["5"])
    
  | LABEL lbl ->
      `Label (pp_label name lbl)

  | MOV (ws, op1, op2) -> pp_instr_binop "mov" ws op1 op2

  | MOVSX (wsd, wss, dst, src) -> pp_movx "movs" wsd wss dst src

  | MOVZX (wsd, wss, dst, src) -> pp_movx "movz" wsd wss dst src

  | CMOVcc (ws, ct, op1, op2) ->
      let iname = Printf.sprintf "cmov%s" (pp_ct ct) in
      pp_instr_binop iname ws op1 op2

  | SETcc (ct, op) ->
      let iname = Printf.sprintf "set%s" (pp_ct ct) in
      `Instr (iname, [pp_opr `U8 op])

  | BT (ws, op, ir) ->
    let rs = rs_of_ws ws in
    `Instr (pp_iname rs "bt", [pp_imr `U8 ir; pp_opr rs op])

  | NEG (ws, op) -> pp_instr_unop "neg" ws op

  | INC (ws, op) -> pp_instr_unop "inc" ws op

  | DEC (ws, op) -> pp_instr_unop "dec" ws op

  | ADD (ws, op1, op2) -> pp_instr_binop "add" ws op1 op2

  | SUB (ws, op1, op2) -> pp_instr_binop "sub" ws op1 op2

  | ADC (ws, op1, op2) -> pp_instr_binop "adc" ws op1 op2

  | SBB (ws, op1, op2) -> pp_instr_binop "sbb" ws op1 op2

  | MUL (ws, op) -> pp_instr_unop "mul" ws op

  | IMUL (ws, op, None) -> pp_instr_unop "imul" ws op

  | IMUL (ws, op1, Some (op2, None)) -> pp_instr_binop "imul" ws op1 op2

  | IMUL (ws, op1, Some (op2, Some i)) ->
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "imul",
              [pp_imm (Conv.bi_of_int32 i); pp_opr rs op2; pp_opr rs op1])

  | DIV (ws, op) -> pp_instr_unop "div" ws op

  | IDIV (ws, op) -> pp_instr_unop "idiv" ws op

  | ADCX(ws, r, op) -> 
    let rs = rs_of_ws ws in
    `Instr (pp_iname rs "adcx", [pp_opr rs op; pp_register rs r])

  | ADOX(ws, r, op) -> 
    let rs = rs_of_ws ws in
    `Instr (pp_iname rs "adox", [pp_opr rs op; pp_register rs r])

  | MULX(ws, r1, r2, op) ->
    let rs = rs_of_ws ws in
    `Instr (pp_iname rs "mulx",
            [pp_opr rs op; pp_register rs r2; pp_register rs r1;])

  | CQO ws ->
    let name =
      match ws with
      | LM.U16 -> "cwd"
      | LM.U32 -> "cdq"
      | LM.U64 -> "cqo"
      | _ -> assert false in
    `Instr (name, [])

  | CMP (ws, op1, op2) -> pp_instr_binop "cmp" ws op1 op2

  | TEST (ws, op1, op2) -> pp_instr_binop "test" ws op1 op2

  | Jcc (label, ct) ->
      let iname = Printf.sprintf "j%s" (pp_ct ct) in
      `Instr (iname, [pp_label name label])

  | JMP label ->
      (* Correct? *)
      `Instr ("jmp", [pp_label name label])

  | LEA (ws, op1, op2) ->
      (* Correct? *)
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "lea", [pp_opr rs op2; pp_register rs op1])

  | NOT (ws, op) -> pp_instr_unop "not" ws op

  | AND (ws, op1, op2) -> pp_instr_binop "and" ws op1 op2

  | ANDN (ws, dst, src1, src2) -> pp_instr_rro "andn" ws dst src1 src2

  | OR (ws, op1, op2) -> pp_instr_binop "or" ws op1 op2

  | XOR (ws, op1, op2) -> pp_instr_binop "xor" ws op1 op2

  | ROR (ws, op, ir) ->
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "ror", [pp_imr `U8 ir; pp_opr rs op])

  | ROL (ws, op, ir) ->
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "rol", [pp_imr `U8 ir; pp_opr rs op])

  | SAL _ ->
    assert false

  | SAR (ws, op, ir) ->
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "sar", [pp_imr `U8 ir; pp_opr rs op])

  | SHL (ws, op, ir) ->
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "shl", [pp_imr `U8 ir; pp_opr rs op])

  | SHR (ws, op, ir) ->
      let rs = rs_of_ws ws in
      `Instr (pp_iname rs "shr", [pp_imr `U8 ir; pp_opr rs op])

  | SHLD (ws, op1, op2, ir) -> pp_sh_d "shld" ws op1 op2 ir

  | SHRD (ws, op1, op2, ir) -> pp_sh_d "shrd" ws op1 op2 ir

  | BSWAP(ws, r) ->
    let rs = rs_of_ws ws in
    `Instr (pp_iname rs "bswap", [pp_register rs r])

  | MOVD (ws, dst, src) ->
      let rs = rs_of_ws ws in
      `Instr ((if ws = U64 then "movq" else "movd"), [pp_opr rs src; pp_xmm_register U128 dst])

  | VMOVDQU (sz, dst, src) ->
    `Instr ("vmovdqu", [pp_rm128 sz src; pp_rm128 sz dst])

  | VPAND (sz, dst, src1, src2) -> pp_rm128_binop "vpand" sz dst src1 src2

  | VPANDN (sz, dst, src1, src2) -> pp_xmm_binop "vpandn" sz dst src1 src2

  | VPOR (sz, dst, src1, src2) -> pp_rm128_binop "vpor" sz dst src1 src2

  | VPXOR (sz, dst, src1, src2) -> pp_rm128_binop "vpxor" sz dst src1 src2

  | VPADD (ve, sz, dst, src1, src2) ->
    `Instr (pp_viname ve "vpadd", [pp_rm128 sz src2; pp_rm128 sz src1; pp_rm128 sz dst])

  | VPSUB (ve, sz, dst, src1, src2) ->
    `Instr (pp_viname ve "vpsub", [pp_rm128 sz src2; pp_rm128 sz src1; pp_rm128 sz dst])

  | VPMULL(ve, sz, dst, src1, src2) ->
    `Instr (pp_viname ve "vpmull", [pp_rm128 sz src2; pp_rm128 sz src1; pp_rm128 sz dst])

  | VPMULU (sz, dst, src1, src2) -> pp_xmm_binop "vpmuludq" sz dst src1 src2

  | VPEXTR (ve, dst, src, i) ->
    let ve' = LM.(match ve with U32 -> VE32 | U64 -> VE64 | _ -> assert false) in
    `Instr (pp_viname ve' "vpextr", [ pp_imm (Conv.bi_of_int8 i); pp_xmm_register U128 src; pp_opr (rs_of_ws ve) dst ])

  | VPINSR (ve, dst, src1, src2, i) ->
    let rs = match ve with
      | LM.VE8 | LM.VE16 | LM.VE32 -> `U32
      | LM.VE64 -> `U64
    in
    `Instr (pp_viname ve "vpinsr", [ pp_imm (Conv.bi_of_int8 i) ; pp_opr rs src2 ; pp_xmm_register U128 src1 ; pp_xmm_register U128 dst ])

  | VPSLL (ve, sz, dst, src1, src2) ->
    `Instr (pp_viname ve "vpsll", [pp_imm (Conv.bi_of_int8 src2); pp_rm128 sz src1; pp_rm128 sz dst])

  | VPSRL (ve, sz, dst, src1, src2) ->
    `Instr (pp_viname ve "vpsrl", [pp_imm (Conv.bi_of_int8 src2); pp_rm128 sz src1; pp_rm128 sz dst])

  | VPSRA (ve, sz, dst, src1, src2) ->
    `Instr (pp_viname ve "vpsra", [pp_imm (Conv.bi_of_int8 src2); pp_rm128 sz src1; pp_rm128 sz dst])

  | VPSLLV (ve, sz, dst, src1, src2) -> pp_xmm_binop (pp_viname ve "vpsllv") sz dst src1 src2
  | VPSRLV (ve, sz, dst, src1, src2) -> pp_xmm_binop (pp_viname ve "vpsrlv") sz dst src1 src2

  | VPSLLDQ (sz, dst, src, i) -> pp_vpsxldq "l" sz dst src i
  | VPSRLDQ (sz, dst, src, i) -> pp_vpsxldq "r" sz dst src i

  | VPSHUFB (sz, dst, src1, src2) -> pp_xmm_binop "vpshufb" sz dst src1 src2

  | VPSHUFD (sz, dst, src1, src2) -> pp_vpshuf "d" sz dst src1 src2
  | VPSHUFHW (sz, dst, src1, src2) -> pp_vpshuf "hw" sz dst src1 src2
  | VPSHUFLW (sz, dst, src1, src2) -> pp_vpshuf "lw" sz dst src1 src2

  | VPUNPCKH (ve, sz, dst, src1, src2) -> pp_vpunpck "h" ve sz dst src1 src2
  | VPUNPCKL (ve, sz, dst, src1, src2) -> pp_vpunpck "l" ve sz dst src1 src2

  | VPBLENDD (sz, dst, src1, src2, mask) -> pp_xxri "vpblendd" sz dst src1 src2 mask
  | VPBROADCAST(ve, sz, dst, src) ->
    `Instr (pp_viname ve "vpbroadcast", [ pp_rm128 U128 src; pp_xmm_register sz dst])
  | VBROADCASTI128(dst, src) ->
    `Instr ("vbroadcasti128", [ pp_m128 src; pp_xmm_register U256 dst])
  | VEXTRACTI128 (dst, src, i) ->
    `Instr ("vextracti128", [ pp_imm (Conv.bi_of_int8 i); pp_xmm_register U256 src ; pp_rm128 U128 dst ])
  | VINSERTI128 (dst, src1, src2, i) ->
    `Instr ("vinserti128", [ pp_imm (Conv.bi_of_int8 i); pp_rm128 U128 src2 ; pp_xmm_register U256 src1 ; pp_xmm_register U256 dst ])
  | VPERM2I128 (dst, src1, src2, i) -> pp_xxri "vperm2i128" U256 dst src1 src2 i
  | VPERMQ (dst, src, i) ->
    `Instr("vpermq", [ pp_imm (Conv.bi_of_int8 i); pp_rm128 U256 src; pp_xmm_register U256 dst ])

(* -------------------------------------------------------------------- *)
let pp_instr name (fmt : Format.formatter) (i : X86_sem.asm) =
  pp_gen fmt (pp_instr name i)

(* -------------------------------------------------------------------- *)
let pp_instrs name (fmt : Format.formatter) (is : X86_sem.asm list) =
  List.iter (Format.fprintf fmt "%a\n%!" (pp_instr name)) is

(* -------------------------------------------------------------------- *)
let align_of_ws =
  function
  | Type.U8 -> 0
  | Type.U16 -> 1
  | Type.U32 -> 2
  | Type.U64 -> 3
  | Type.U128 -> 4
  | Type.U256 -> 5

let pp_align ws =
  let n = align_of_ws ws in
  Format.sprintf "%d" n

let decl_of_ws =
  function
  | Type.U8 -> Some ".byte"
  | Type.U16 -> Some ".word"
  | Type.U32 -> Some ".long"
  | Type.U64 -> Some ".quad"
  | Type.U128 | Type.U256 -> None

let bigint_to_bytes n z =
  let base = Bigint.of_int 256 in
  let res = ref [] in
  let z = ref z in
  for i = 1 to n do
    let q, r = Bigint.ediv !z base in
    z := q;
    res := r :: !res
  done;
  !res

let pp_const ws z =
  match decl_of_ws ws with
  | Some d -> [ `Instr (d, [Bigint.to_string z]) ]
  | None ->
    List.rev_map (fun b -> `Instr (".byte", [ Bigint.to_string b] ))
      (bigint_to_bytes (Prog.size_of_ws ws) z)

let pp_glob_def fmt (gd:Expr.glob_decl) : unit =
  let (ws,n,z) = Conv.gd_of_cgd gd in
  let z = Prog.clamp ws z in
  let m = mangle n in
  pp_gens fmt ([
    `Instr (".globl", [m]);
    `Instr (".globl", [n]);
    `Instr (".p2align", [pp_align ws]);
    `Label m;
    `Label n
  ] @ pp_const ws z)

(* -------------------------------------------------------------------- *)
type 'a tbl = 'a Conv.coq_tbl
type  gd_t  = Expr.glob_decl list 

let pp_prog (tbl: 'info tbl) (fmt : Format.formatter) 
   ((gd:gd_t), (asm : X86_sem.xprog)) =
  pp_gens fmt
    [`Instr (".text"   , []);
     `Instr (".p2align", ["5"])];

  List.iter (fun (n, _) -> pp_gens fmt
    [`Instr (".globl", [mangle (string_of_funname tbl n)]);
     `Instr (".globl", [string_of_funname tbl n])])
    asm;

  let open X86_sem in
  let open Prog in
  List.iter (fun (n, d) ->
      let name = string_of_funname tbl n in
      let stsz  = Conv.bi_of_z d.xfd_stk_size in
      let tosave, saved_stack = d.xfd_extra in
      pp_gens fmt [
        `Label (mangle (string_of_funname tbl n));
        `Label name
      ];
      List.iter (fun r ->
        pp_gens fmt [`Instr ("pushq", [pp_register `U64 r])])
        tosave;
      begin match saved_stack with
      | SavedStackNone  -> 
        assert (Bigint.equal stsz Bigint.zero);
        pp_instrs name fmt d.X86_sem.xfd_body;
      | SavedStackReg r ->
        pp_instrs name fmt
          [ MOV(uptr, Reg_op r, Reg_op RSP);
            SUB(uptr, Reg_op RSP, Imm_op (Conv.int64_of_bi stsz));
            AND(uptr, Reg_op RSP, Imm_op (Conv.int64_of_bi (B.of_int (-32))));
          ];
        pp_instrs name fmt d.X86_sem.xfd_body;
        pp_instrs name fmt 
          [ MOV(uptr, Reg_op RSP, Reg_op r) ]
  
      | SavedStackStk p -> 
        let adr = Adr_op { ad_disp  = Conv.int64_of_bi (Conv.bi_of_z p);
                    ad_base   = Some RSP;
                    ad_scale  = Scale1;
                    ad_offset = None} in
        pp_instrs name fmt 
          [ MOV(uptr, Reg_op RBP, Reg_op RSP);
            SUB(uptr, Reg_op RSP, Imm_op (Conv.int64_of_bi stsz));
            AND(uptr, Reg_op RSP, Imm_op (Conv.int64_of_bi (B.of_int (-32))));
            MOV(uptr, adr , Reg_op RBP)
          ];
        pp_instrs name fmt d.X86_sem.xfd_body;
        pp_instrs name fmt
          [ MOV(uptr, Reg_op RSP, adr) ] 
      end;
      List.iter (fun r ->
          pp_gens fmt [`Instr ("popq", [pp_register `U64 r])])
        (List.rev tosave);
      pp_gens fmt [`Instr ("ret", [])]) asm;

  if not (List.is_empty gd) then
    pp_gens fmt [`Instr (".data", [])];

  List.iter (pp_glob_def fmt) gd
