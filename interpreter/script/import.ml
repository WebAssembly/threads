open Source
open Types
open Ast

module Unknown = Error.Make ()
exception Unknown = Unknown.Error  (* indicates unknown import name *)

module Registry = Map.Make(struct type t = Ast.name let compare = compare end)

type registry = (name -> extern_type -> Instance.extern option) Registry.t ref

type lookup_export = name -> extern_type -> Instance.extern option


let global : registry = ref Registry.empty
let registry () : registry = ref !global

let register r name lookup = r := Registry.add name lookup !r
let register_global name lookup = register global name lookup

let lookup r module_name item_name et : Instance.extern option =
  match Registry.find_opt module_name !r with
  | Some f -> f item_name et
  | None -> None

let lookup_import r (m : module_) (im : import) : Instance.extern =
  let {module_name; item_name; idesc} = im.it in
  let et = import_type m im in
    match lookup r module_name item_name et with
    | Some ext -> ext
    | None ->
      Unknown.error im.at
        ("unknown import \"" ^ string_of_name module_name ^
          "\".\"" ^ string_of_name item_name ^ "\"")

let link r m = List.map (lookup_import r m) m.it.imports
