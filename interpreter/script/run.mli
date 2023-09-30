type context

exception Abort of Source.region * string
exception Assert of Source.region * string
exception IO of Source.region * string

val trace : string -> unit

val context : unit -> context

val run_string : context -> string -> bool
val run_file : context -> string -> bool
val run_stdin : context -> unit
