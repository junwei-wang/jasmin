%{
  module L = Location
  module S = Syntax

  open Syntax

  let setsign c s = 
    match c with
    | None -> Some (L.mk_loc (L.loc s) (CSS(None, L.unloc s)))
    | _    -> c

%}

%token EOF

%token LBRACKET
%token RBRACKET
%token LBRACE
%token RBRACE
%token LPAREN
%token RPAREN

%token T_BOOL
%token T_U8 T_U16 T_U32 T_U64 T_U128 T_U256 T_INT 

%token SHARP
%token AMP
%token AMPAMP
%token BANG
%token BANGEQ
%token COLON
%token COMMA
%token DOWNTO
%token ELSE
%token EQ
%token EQEQ
%token EXEC
%token FALSE
%token FN
%token FOR
%token <Syntax.sign>GE
%token GLOBAL
%token <Syntax.sign>GT
%token <Syntax.sign>GTGT
%token HAT
%token IF
%token INLINE
%token <Syntax.sign> LE
%token <Syntax.sign> LT
%token               LTLT
%token MINUS
%token PARAM
%token PERCENT
%token PIPE
%token PIPEPIPE
%token PLUS
%token QUESTIONMARK
%token RARROW
%token REG
%token RETURN
%token SEMICOLON
%token <Syntax.swsize>SWSIZE
%token <Syntax.svsize> SVSIZE
%token SLASH
%token STACK
%token STAR
%token TO
%token TRUE
%token UNDERSCORE
%token WHILE
%token EXPORT
%token ARRAYINIT
%token <string> NID
%token <Bigint.zint> INT

%nonassoc COLON QUESTIONMARK
%left PIPEPIPE
%left AMPAMP
%left EQEQ BANGEQ
%left LE GE LT GT
%left PIPE
%left HAT
%left AMP
%left LTLT GTGT
%left PLUS MINUS
%left STAR SLASH PERCENT
%nonassoc BANG 

%type <Syntax.pprogram> module_

%start module_

%%

%inline ident:
| x=loc(NID) { x }

var:
| x=ident { x }

(* ** Type expressions
 * -------------------------------------------------------------------- *)

utype:
| T_U8   { `W8   }
| T_U16  { `W16  }
| T_U32  { `W32  }
| T_U64  { `W64  }
| T_U128 { `W128 }
| T_U256 { `W256 }

ptype_r:
| T_BOOL
    { TBool }

| T_INT
    { TInt }

| ut=utype
    { TWord ut }

| ut=utype d=brackets(pexpr)
    { TArray (ut, d) }

ptype:
| x=loc(ptype_r) { x }

swsize:
| s=SWSIZE { s }

svsize:
| s=SVSIZE { s }

castop1:
| s=swsize { CSS (Some (fst s), snd s) }
| s=svsize { CVS s }

castop:
| c=loc(castop1)? { c }

cast: 
| T_INT    { `ToInt }
| s=swsize { `ToWord s }

(* ** Index expressions
 * -------------------------------------------------------------------- *)
%inline peop1:
| BANG  c=castop    { `Not c  }
| MINUS c=castop    { `Neg c  }

%inline peop2:
| AMPAMP               { `And   }
| PIPEPIPE             { `Or    }
| PLUS        c=castop { `Add  c}
| MINUS       c=castop { `Sub  c}
| STAR        c=castop { `Mul  c}
| SLASH       c=castop { `Div  c}
| PERCENT     c=castop { `Mod  c}
| AMP         c=castop { `BAnd c}
| PIPE        c=castop { `BOr  c}
| HAT         c=castop { `BXOr c}
| LTLT        c=castop { `ShL  c} 
| s=loc(GTGT) c=castop { `ShR (setsign c s)}
| EQEQ        c=castop { `Eq   c}
| BANGEQ      c=castop { `Neq  c}
| s=loc(LT)   c=castop { `Lt  (setsign c s)}
| s=loc(LE)   c=castop { `Le  (setsign c s)}
| s=loc(GT)   c=castop { `Gt  (setsign c s)}
| s=loc(GE)   c=castop { `Ge  (setsign c s)}

prim:
| SHARP x=ident { x }

pexpr_r:
| v=var
    { PEVar v }

| v=var i=brackets(pexpr)
    { PEGet (v, i) }

| TRUE
    { PEBool true }

| FALSE
    { PEBool false }

| i=INT
    { PEInt i }

| ct=parens(utype)? LBRACKET v=var PLUS e=pexpr RBRACKET
    { PEFetch (ct, v, e) }

| ct=parens(svsize) LBRACKET es=rtuple1(pexpr) RBRACKET
    { PEpack(ct,es) }

| ct=parens(cast) e=pexpr %prec BANG
    { PEOp1 (`Cast(ct), e) }

| o=peop1 e=pexpr
    { PEOp1 (o, e) }

| e1=pexpr o=peop2 e2=pexpr
    { PEOp2 (o, (e1, e2)) }

| e=parens(pexpr)
    { PEParens e }

| f=var args=parens_tuple(pexpr)
    { PECall (f, args) }

| f=prim args=parens_tuple(pexpr)
    { PEPrim (f, args) }

| e1=pexpr QUESTIONMARK e2=pexpr COLON e3=pexpr
    { PEIf(e1, e2, e3) }

pexpr:
| e=loc(pexpr_r) { e }

(* -------------------------------------------------------------------- *)
peqop:
|                EQ  { `Raw    }
| PLUS  c=castop EQ  { `Add  c }
| MINUS c=castop EQ  { `Sub  c }
| STAR  c=castop EQ  { `Mul  c }
| GTGT  c=castop EQ  { `ShR  c }
| LTLT  c=castop EQ  { `ShL  c }
| AMP   c=castop EQ  { `BAnd c }
| HAT   c=castop EQ  { `BXOr c }
| PIPE  c=castop EQ  { `BOr  c }

(* ** Left value
 * -------------------------------------------------------------------- *)
plvalue_r:
| UNDERSCORE
    { PLIgnore }

| x=var
    { PLVar x }

| x=var i=brackets(pexpr)
    { PLArray (x, i) }

| ct=parens(utype)? LBRACKET v=var PLUS e=pexpr RBRACKET
    { PLMem (ct, v, e) }

plvalue:
| x=loc(plvalue_r) { x }

(* ** Control instructions
 * -------------------------------------------------------------------- *)

pinstr_r:
| ARRAYINIT LPAREN x=var RPAREN SEMICOLON
    { PIArrayInit x }

| x=tuple1(plvalue) o=peqop e=pexpr c=prefix(IF, pexpr)? SEMICOLON
    { PIAssign (x, o, e, c) }

| fc=loc(f=var args=parens_tuple(pexpr) { (f, args) })
    c=prefix(IF, pexpr)? SEMICOLON
    { let { L.pl_loc = loc; L.pl_desc = (f, args) } = fc in
      PIAssign ([], `Raw, L.mk_loc loc (PECall (f, args)), c) }

| IF c=pexpr i1s=pblock
    { PIIf (c, i1s, None) }

| IF c=pexpr i1s=pblock ELSE i2s=pblock
    { PIIf (c, i1s, Some i2s) }

| FOR v=var EQ ce1=pexpr TO ce2=pexpr is=pblock
    { PIFor (v, (`Up, ce1, ce2), is) }

| FOR v=var EQ ce1=pexpr DOWNTO ce2=pexpr is=pblock
    { PIFor (v, (`Down, ce2, ce1), is) }

| WHILE is1=pblock? LPAREN b=pexpr RPAREN is2=pblock?
    { PIWhile (is1, b, is2) }

pinstr:
| i=loc(pinstr_r) { i }

pblock_r:
| s=braces(pinstr*) { s }

pblock:
| s=loc(pblock_r) { s }

(* ** Function definitions
 * -------------------------------------------------------------------- *)

stor_type:
| sto=storage ty=ptype { (sto, ty) }

storage:
| REG    { `Reg    }
| STACK  { `Stack  }
| INLINE { `Inline }
| GLOBAL { `Global }

%inline pvardecl(S):
| ty=stor_type vs=separated_nonempty_list(S, var) { (ty, vs) }

pfunbody :
| LBRACE
    vs = postfix(pvardecl(COMMA?), SEMICOLON)*
    is = pinstr*
    rt = option(RETURN vs=tuple(var) SEMICOLON { vs })
  RBRACE
    { { pdb_vars  = vs;
        pdb_instr = is;
        pdb_ret   = rt; } }

call_conv :
| EXPORT { `Export }
| INLINE { `Inline }

pfundef:
| cc=call_conv? FN
    name = ident
    args = parens_tuple(pvardecl(empty))
    rty  = prefix(RARROW, tuple(stor_type))?
    body = pfunbody

  { { pdf_cc   = cc;
      pdf_name = name;
      pdf_args = 
        List.flatten (List.map (fun (str, ids) -> List.map (fun id -> (str, id)) ids) args);
      pdf_rty  = rty ;
      pdf_body = body; } }

(* -------------------------------------------------------------------- *)
pparam:
| PARAM ty=ptype x=ident EQ pe=pexpr SEMICOLON
    { { ppa_ty = ty; ppa_name = x; ppa_init = pe; } }

(* -------------------------------------------------------------------- *)
pglobal:
| pgd_type=ptype pgd_name=ident EQ pgd_val=pexpr SEMICOLON
  { { pgd_type ; pgd_name ; pgd_val  } }

(* -------------------------------------------------------------------- *)
pexec:
| EXEC pex_name=ident pex_mem=parens_tuple(range) { { pex_name ; pex_mem } }

range:
| ptr=INT COLON size=INT { ptr, size }

(* -------------------------------------------------------------------- *)
top:
| x=pfundef { S.PFundef x }
| x=pparam  { S.PParam  x }
| x=pglobal { S.PGlobal x }
| x=pexec   { S.Pexec   x }
(* -------------------------------------------------------------------- *)
module_:
| pfs=loc(top)* EOF
    { pfs }

| error
   { S.parse_error (L.make $startpos $endpos) }

(* -------------------------------------------------------------------- *)
%inline empty:
| (* empty *) { () }

%inline plist1(X, S):
| s=separated_nonempty_list(S, X) { s }

%inline loc(X):
| x=X { L.mk_loc (L.make $startpos $endpos) x }

%inline prefix(S, X):
| S x=X { x }

%inline postfix(X, S):
| x=X S { x }

%inline parens(X):
| x=delimited(LPAREN, X, RPAREN) { x }

%inline brackets(X):
| x=delimited(LBRACKET, X, RBRACKET) { x }

%inline braces(X):
| x=delimited(LBRACE, X, RBRACE) { x }

%inline rtuple(X):
| s=separated_list(COMMA, X) { s }

%inline rtuple1(X):
| s=separated_nonempty_list(COMMA, X) { s }

%inline tuple(X):
| s=parens(rtuple(X)) | s=rtuple(X) { s }

%inline tuple1(X):
| s=parens(rtuple1(X)) | s=rtuple1(X) { s }

%inline parens_tuple(X):
| s=parens(rtuple(X)) { s }

%inline brackets_tuple(X):
| s=brackets(rtuple(X)) { s }
