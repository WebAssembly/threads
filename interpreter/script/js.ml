open Types
open Ast
open Script
open Source


(* Harness *)

let harness =
{|
'use strict';

let spectest = {
  print: console.log.bind(console),
  print_i32: console.log.bind(console),
  print_i32_f32: console.log.bind(console),
  print_f64_f64: console.log.bind(console),
  print_f32: console.log.bind(console),
  print_f64: console.log.bind(console),
  global_i32: 666,
  global_f32: 666,
  global_f64: 666,
  table: new WebAssembly.Table({initial: 10, maximum: 20, element: 'anyfunc'}),
  memory: new WebAssembly.Memory({initial: 1, maximum: 2})
};
let handler = {
  get(target, prop) {
    return (prop in target) ?  target[prop] : {};
  }
};
let registry = new Proxy({spectest}, handler);

function register(name, instanceObj) {
  registry[name] = instanceObj.instance.exports;
}

function module(bytes, valid = true) {
  let buffer = new ArrayBuffer(bytes.length);
  let view = new Uint8Array(buffer);
  for (let i = 0; i < bytes.length; ++i) {
    view[i] = bytes.charCodeAt(i);
  }
  let validated;
  try {
    validated = WebAssembly.validate(buffer);
  } catch (e) {
    throw new Error("Wasm validate throws");
  }
  if (validated !== valid) {
    throw new Error("Wasm validate failure" + (valid ? "" : " expected"));
  }
  return new WebAssembly.Module(buffer);
}

function instance(bytes, imports = registry) {
  const mod = module(bytes);
  const instance = new WebAssembly.Instance(mod, imports);
  return {module: mod, instance};
}

function call(instanceObj, name, args) {
  return instanceObj.instance.exports[name](...args);
}

function get(instanceObj, name) {
  let v = instanceObj.instance.exports[name];
  return (v instanceof WebAssembly.Global) ? v.value : v;
}

function exports(name, instanceObj) {
  return {[name]: instanceObj.instance.exports};
}

function run(action) {
  action();
}

function assert_malformed(bytes) {
  try { module(bytes, false) } catch (e) {
    if (e instanceof WebAssembly.CompileError) return;
  }
  throw new Error("Wasm decoding failure expected");
}

function assert_invalid(bytes) {
  try { module(bytes, false) } catch (e) {
    if (e instanceof WebAssembly.CompileError) return;
  }
  throw new Error("Wasm validation failure expected");
}

function assert_unlinkable(bytes) {
  let mod = module(bytes);
  try { new WebAssembly.Instance(mod, registry) } catch (e) {
    if (e instanceof WebAssembly.LinkError) return;
  }
  throw new Error("Wasm linking failure expected");
}

function assert_uninstantiable(bytes) {
  let mod = module(bytes);
  try { new WebAssembly.Instance(mod, registry) } catch (e) {
    if (e instanceof WebAssembly.RuntimeError) return;
  }
  throw new Error("Wasm trap expected");
}

function assert_trap(action) {
  try { action() } catch (e) {
    if (e instanceof WebAssembly.RuntimeError) return;
  }
  throw new Error("Wasm trap expected");
}

let StackOverflow;
try { (function f() { 1 + f() })() } catch (e) { StackOverflow = e.constructor }

function assert_exhaustion(action) {
  try { action() } catch (e) {
    if (e instanceof StackOverflow) return;
  }
  throw new Error("Wasm resource exhaustion expected");
}

function assert_return(action, ...expected) {
  let actual = action();
  if (actual === undefined) {
    actual = [];
  } else if (!Array.isArray(actual)) {
    actual = [actual];
  }
  if (actual.length !== expected.length) {
    throw new Error(expected.length + " value(s) expected, got " + actual.length);
  }
  for (let i = 0; i < actual.length; ++i) {
    match_result(actual[i], expected[i]);
  }
}

function match_result(actual, expected) {
  switch (expected) {
    case "nan:canonical":
    case "nan:arithmetic":
    case "nan:any":
      // Note that JS can't reliably distinguish different NaN values,
      // so there's no good way to test that it's a canonical NaN.
      if (!Number.isNaN(actual)) {
        throw new Error("Wasm return value NaN expected, got " + actual);
      };
      return;
    default:
      if (Array.isArray(expected)) {
        for (let i = 0; i < expected.length; ++i) {
          try {
            match_result(actual, expected[i]);
            return;
          } catch (e) {}
        }
        throw new Error("Wasm return value in " + expected + " expected, got " + actual);
      }
      if (!Object.is(actual, expected)) {
        throw new Error("Wasm return value " + expected + " expected, got " + actual);
      };
  }
}

function thread(shared, f) {
  // TODO: spawn thread, share instances, and run f in it; return a handle for the thread
}

function wait(t) {
  // TODO: wait for thread t to terminate
}
|}


(* Context *)

module NameMap = Map.Make(struct type t = Ast.name let compare = compare end)
module Map = Map.Make(String)

type 'a defs = {mutable env : 'a Map.t; mutable current : int}
type exports = extern_type NameMap.t
type context = {modules : exports defs; threads : unit defs}

let exports m : exports =
  List.fold_left
    (fun map exp -> NameMap.add exp.it.name (export_type m exp) map)
    NameMap.empty m.it.exports

let defs () : 'a defs = {env = Map.empty; current = 0}
let context () : context = {modules = defs (); threads = defs ()}

let current_var (defs : 'a defs) = "$" ^ string_of_int defs.current
let of_var_opt (defs : 'a defs) = function
  | None -> current_var defs
  | Some x -> x.it

let bind (defs : 'a defs) x_opt desc =
  defs.current <- defs.current + 1;
  defs.env <- Map.add (of_var_opt defs x_opt) desc defs.env;
  if x_opt <> None then defs.env <- Map.add (current_var defs) desc defs.env

let lookup (defs : 'a defs) x_opt at =
  try Map.find (of_var_opt defs x_opt) defs.env with Not_found ->
    raise (Eval.Crash (at, 
      if x_opt = None then "no definition within script"
      else "unknown definition " ^ of_var_opt defs x_opt ^ " within script"))

let lookup_export (mods : exports defs) x_opt name at =
  let exports = lookup mods x_opt at in
  try NameMap.find name exports with Not_found ->
    raise (Eval.Crash (at, "unknown export \"" ^
      string_of_name name ^ "\" within module"))


(* Wrappers *)

let eq_of = function
  | I32Type -> Values.I32 I32Op.Eq
  | I64Type -> Values.I64 I64Op.Eq
  | F32Type -> Values.F32 F32Op.Eq
  | F64Type -> Values.F64 F64Op.Eq

let and_of = function
  | I32Type | F32Type -> Values.I32 I32Op.And
  | I64Type | F64Type -> Values.I64 I64Op.And

let reinterpret_of = function
  | I32Type -> I32Type, Nop
  | I64Type -> I64Type, Nop
  | F32Type -> I32Type, Convert (Values.I32 I32Op.ReinterpretFloat)
  | F64Type -> I64Type, Convert (Values.I64 I64Op.ReinterpretFloat)

let canonical_nan_of = function
  | I32Type | F32Type -> Values.I32 (F32.to_bits F32.pos_nan)
  | I64Type | F64Type -> Values.I64 (F64.to_bits F64.pos_nan)

let abs_mask_of = function
  | I32Type | F32Type -> Values.I32 Int32.max_int
  | I64Type | F64Type -> Values.I64 Int64.max_int

let invoke ft lits at =
  [ft @@ at], FuncImport (1l @@ at) @@ at,
  List.map (fun lit -> Const lit @@ at) lits @ [Call (0l @@ at) @@ at]

let get t at =
  [], GlobalImport t @@ at, [GlobalGet (0l @@ at) @@ at]

let run ts at =
  [], []

let assert_return ress ts at =
  let rec test res =
    match res.it with
    | LitResult lit ->
      let t', reinterpret = reinterpret_of (Values.type_of lit.it) in
      [ reinterpret @@ at;
        Const lit @@ at;
        reinterpret @@ at;
        Compare (eq_of t') @@ at;
        Test (Values.I32 I32Op.Eqz) @@ at;
        BrIf (0l @@ at) @@ at ]
    | NanResult nanop ->
      let nan =
        match nanop.it with
        | Values.I32 _ | Values.I64 _ -> assert false
        | Values.F32 n | Values.F64 n -> n
      in
      let nan_bitmask_of =
        match nan with
        | CanonicalNan -> abs_mask_of (* must only differ from the canonical NaN in its sign bit *)
        | ArithmeticNan -> canonical_nan_of (* can be any NaN that's one everywhere the canonical NaN is one *)
      in
      let t = Values.type_of nanop.it in
      let t', reinterpret = reinterpret_of t in
      [ reinterpret @@ at;
        Const (nan_bitmask_of t' @@ at) @@ at;
        Binary (and_of t') @@ at;
        Const (canonical_nan_of t' @@ at) @@ at;
        Compare (eq_of t') @@ at;
        Test (Values.I32 I32Op.Eqz) @@ at;
        BrIf (0l @@ at) @@ at ]
    | EitherResult ress ->
      [ Block (ValBlockType None,
          List.map (fun res ->
            Block (ValBlockType None,
              test res @
              [Br (1l @@ res.at) @@ res.at]
            ) @@ res.at
          ) ress @
          [Br (1l @@ at) @@ at]
        ) @@ at
      ]
  in [], List.flatten (List.rev_map test ress)

let wrap module_name item_name wrap_action wrap_assertion at =
  let itypes, idesc, action = wrap_action at in
  let locals, assertion = wrap_assertion at in
  let types = (FuncType ([], []) @@ at) :: itypes in
  let imports = [{module_name; item_name; idesc} @@ at] in
  let item = (match idesc.it with FuncImport _ -> 1l | _ -> 0l) @@ at in
  let edesc = FuncExport item @@ at in
  let exports = [{name = Utf8.decode "run"; edesc} @@ at] in
  let body =
    [ Block (ValBlockType None, action @ assertion @ [Return @@ at]) @@ at;
      Unreachable @@ at ]
  in
  let funcs = [{ftype = 0l @@ at; locals; body} @@ at] in
  let m = {empty_module with types; funcs; imports; exports} @@ at in
  Encode.encode m


let is_js_value_type = function
  | I32Type -> true
  | I64Type | F32Type | F64Type -> false

let is_js_global_type = function
  | GlobalType (t, mut) -> is_js_value_type t && mut = Immutable

let is_js_func_type = function
  | FuncType (ins, out) -> List.for_all is_js_value_type (ins @ out)


(* Script conversion *)

let add_hex_char buf c = Printf.bprintf buf "\\x%02x" (Char.code c)
let add_char buf c =
  if c < '\x20' || c >= '\x7f' then
    add_hex_char buf c
  else begin
    if c = '\"' || c = '\\' then Buffer.add_char buf '\\';
    Buffer.add_char buf c
  end
let add_unicode_char buf uc =
  if uc < 0x20 || uc >= 0x7f then
    Printf.bprintf buf "\\u{%02x}" uc
  else
    add_char buf (Char.chr uc)

let of_string_with iter add_char s =
  let buf = Buffer.create 256 in
  Buffer.add_char buf '\"';
  iter (add_char buf) s;
  Buffer.add_char buf '\"';
  Buffer.contents buf

let of_bytes = of_string_with String.iter add_hex_char
let of_string = of_string_with String.iter add_char
let of_name = of_string_with List.iter add_unicode_char

let of_float z =
  match string_of_float z with
  | "nan" -> "NaN"
  | "-nan" -> "-NaN"
  | "inf" -> "Infinity"
  | "-inf" -> "-Infinity"
  | s -> s

let of_literal lit =
  match lit.it with
  | Values.I32 i -> I32.to_string_s i
  | Values.I64 i -> "int64(\"" ^ I64.to_string_s i ^ "\")"
  | Values.F32 z -> of_float (F32.to_float z)
  | Values.F64 z -> of_float (F64.to_float z)

let of_nan = function
  | CanonicalNan -> "nan:canonical"
  | ArithmeticNan -> "nan:arithmetic"

let rec of_result res =
  match res.it with
  | LitResult lit -> of_literal lit
  | NanResult nanop ->
    (match nanop.it with
    | Values.I32 _ | Values.I64 _ -> assert false
    | Values.F32 n | Values.F64 n -> of_nan n
    )
  | EitherResult ress ->
    "[" ^ String.concat ", " (List.map of_result ress) ^ "]"

let rec of_definition def =
  match def.it with
  | Textual m -> of_bytes (Encode.encode m)
  | Encoded (_, bs) -> of_bytes bs
  | Quoted (_, s) ->
    try of_definition (Parse.string_to_module s) with Parse.Syntax _ ->
      of_bytes "<malformed quote>"

let of_wrapper c x_opt name wrap_action wrap_assertion at =
  let x = of_var_opt c.modules x_opt in
  let bs = wrap (Utf8.decode x) name wrap_action wrap_assertion at in
  "call(instance(" ^ of_bytes bs ^ ", " ^
    "exports(" ^ of_string x ^ ", " ^ x ^ ")), " ^ " \"run\", [])"

let of_action c act =
  match act.it with
  | Invoke (x_opt, name, lits) ->
    "call(" ^ of_var_opt c.modules x_opt ^ ", " ^ of_name name ^ ", " ^
      "[" ^ String.concat ", " (List.map of_literal lits) ^ "])",
    (match lookup_export c.modules x_opt name act.at with
    | ExternFuncType ft when not (is_js_func_type ft) ->
      let FuncType (_, out) = ft in
      Some (of_wrapper c x_opt name (invoke ft lits), out)
    | _ -> None
    )
  | Get (x_opt, name) ->
    "get(" ^ of_var_opt c.modules x_opt ^ ", " ^ of_name name ^ ")",
    (match lookup_export c.modules x_opt name act.at with
    | ExternGlobalType gt when not (is_js_global_type gt) ->
      let GlobalType (t, _) = gt in
      Some (of_wrapper c x_opt name (get gt), [t])
    | _ -> None
    )
  | Eval -> assert false

let of_assertion' c act name args wrapper_opt =
  let act_js, act_wrapper_opt = of_action c act in
  let js = name ^ "(() => " ^ act_js ^ String.concat ", " ("" :: args) ^ ")" in
  match act_wrapper_opt with
  | None -> js ^ ";"
  | Some (act_wrapper, out) ->
    let run_name, wrapper =
      match wrapper_opt with
      | None -> name, run
      | Some wrapper -> "run", wrapper
    in run_name ^ "(() => " ^ act_wrapper (wrapper out) act.at ^ ");  // " ^ js

let of_assertion c ass =
  match ass.it with
  | AssertMalformed (def, _) ->
    "assert_malformed(" ^ of_definition def ^ ");"
  | AssertInvalid (def, _) ->
    "assert_invalid(" ^ of_definition def ^ ");"
  | AssertUnlinkable (def, _) ->
    "assert_unlinkable(" ^ of_definition def ^ ");"
  | AssertUninstantiable (def, _) ->
    "assert_uninstantiable(" ^ of_definition def ^ ");"
  | AssertReturn (act, ress) ->
    of_assertion' c act "assert_return" (List.map of_result ress)
      (Some (assert_return ress))
  | AssertTrap (act, _) ->
    of_assertion' c act "assert_trap" [] None
  | AssertExhaustion (act, _) ->
    of_assertion' c act "assert_exhaustion" [] None

let rec of_command c cmd =
  "\n// " ^ Filename.basename cmd.at.left.file ^
    ":" ^ string_of_int cmd.at.left.line ^ "\n" ^
  match cmd.it with
  | Module (x_opt, def) ->
    let rec unquote def =
      match def.it with
      | Textual m -> m
      | Encoded (_, bs) -> Decode.decode "binary" bs
      | Quoted (_, s) -> unquote (Parse.string_to_module s)
    in bind c.modules x_opt (exports (unquote def));
    "let " ^ current_var c.modules ^
    " = instance(" ^ of_definition def ^ ");\n" ^
    (if x_opt = None then "" else
    "let " ^ of_var_opt c.modules x_opt ^
    " = " ^ current_var c.modules ^ ";\n")
  | Register (name, x_opt) ->
    "register(" ^ of_name name ^ ", " ^ of_var_opt c.modules x_opt ^ ");\n"
  | Action act ->
    of_assertion' c act "run" [] None ^ "\n"
  | Assertion ass ->
    of_assertion c ass ^ "\n"
  | Thread (x_opt, xs, cmds) ->
    "let " ^ current_var c.threads ^
    " = thread([" ^
    String.concat ", " (List.map (fun x -> "\"" ^ x.it ^ "\"") xs) ^
    "], function () {" ^
    String.concat "" (List.map (of_command c) cmds) ^
    "});\n"
  | Wait x_opt ->
    "wait(" ^ of_var_opt c.threads x_opt ^ ");\n"
  | Meta _ -> assert false

let of_script scr =
  (if !Flags.harness then harness else "") ^
  String.concat "" (List.map (of_command (context ())) scr)
