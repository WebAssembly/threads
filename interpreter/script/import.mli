open Types
open Ast

type registry

exception Unknown of Source.region * string

val registry : unit -> registry

val lookup : registry -> name -> name -> extern_type -> Instance.extern option
val link : registry -> module_ -> Instance.extern list (* raises Unknown *)


type lookup_export = name -> extern_type -> Instance.extern option

val register : registry -> name -> lookup_export -> unit
val register_global : name -> lookup_export -> unit
