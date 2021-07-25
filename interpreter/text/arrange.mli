open Sexpr

val instr : Ast.instr -> sexpr
val func : Ast.func -> sexpr
val module_ : Ast.module_ -> sexpr
val command : [`Textual | `Binary] -> Script.command -> sexpr list
val script : [`Textual | `Binary] -> Script.script -> sexpr list
