type var = string Source.phrase

type definition = definition' Source.phrase
and definition' =
  | Textual of Ast.module_
  | Encoded of string * string
  | Quoted of string * string

type action = action' Source.phrase
and action' =
  | Invoke of var option * Ast.name * Ast.literal list
  | Get of var option * Ast.name
  | Eval

type nanop = nanop' Source.phrase
and nanop' = (unit, unit, nan, nan) Values.op
and nan = CanonicalNan | ArithmeticNan

type result = result' Source.phrase
and result' =
  | LitResult of Ast.literal
  | NanResult of nanop
  | EitherResult of result list

type assertion = assertion' Source.phrase
and assertion' =
  | AssertMalformed of definition * string
  | AssertInvalid of definition * string
  | AssertUnlinkable of definition * string
  | AssertUninstantiable of definition * string
  | AssertReturn of action * result list
  | AssertTrap of action * string
  | AssertExhaustion of action * string

type command = command' Source.phrase
and command' =
  | Module of var option * definition
  | Register of Ast.name * var option
  | Action of action
  | Assertion of assertion
  | Thread of var option * var list * command list
  | Wait of var option
  | Meta of meta

and meta = meta' Source.phrase
and meta' =
  | Input of var option * string
  | Output of var option * string option
  | Script of var option * (* s1 : *) script * (* s2 : *) script * (* q : *) script
    (* s1 @ s2 is remaining script to run
     * q is script quote of original commands with inputs expanded (reversed)
     * s1 contains reduced commands that must not be quoted
     * s2 contains original commands that still need quoting
     *)

and script = command list

exception Syntax of Source.region * string
