type config

exception Abort of Source.region * string
exception Assert of Source.region * string
exception IO of Source.region * string

val trace : string -> unit

val config : unit -> config

val run_string : config -> string -> bool
val run_file : config -> string -> bool
val run_stdin : config -> unit
