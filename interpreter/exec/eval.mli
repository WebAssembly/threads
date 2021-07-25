open Values
open Instance

type config
type thread_id
type status = Running | Result of value list | Trap of exn

exception Link of Source.region * string
exception Trap of Source.region * string
exception Crash of Source.region * string
exception Exhaustion of Source.region * string

val empty_config : config

val spawn : config -> thread_id * config
val clear : config -> thread_id -> config
val status : config -> thread_id -> status
val step : config -> thread_id -> config
val invoke : config -> thread_id -> func_inst -> value list -> config (* raises Trap *)
val init : config -> thread_id -> Ast.module_ -> extern list -> module_inst * config (* raises Link, Trap *)
