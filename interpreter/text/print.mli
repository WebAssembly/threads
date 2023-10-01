val instr : out_channel -> int -> Ast.instr -> unit
val func : out_channel -> int -> Ast.func -> unit
val module_ : out_channel -> int -> Ast.module_ -> unit
val command : out_channel -> int -> [`Textual | `Binary] -> Script.command -> unit
val script : out_channel -> int -> [`Textual | `Binary] -> Script.script -> unit
