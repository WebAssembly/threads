open Script
open Source


(* Errors & Tracing *)

module Abort = Error.Make ()
module Assert = Error.Make ()
module IO = Error.Make ()

exception Abort = Abort.Error
exception Assert = Assert.Error
exception IO = IO.Error

let trace name = if !Flags.trace then print_endline ("-- " ^ name)


(* File types *)

let binary_ext = "wasm"
let sexpr_ext = "wat"
let script_binary_ext = "bin.wast"
let script_ext = "wast"
let js_ext = "js"

let dispatch_file_ext on_binary on_sexpr on_script_binary on_script on_js file =
  if Filename.check_suffix file binary_ext then
    on_binary file
  else if Filename.check_suffix file sexpr_ext then
    on_sexpr file
  else if Filename.check_suffix file script_binary_ext then
    on_script_binary file
  else if Filename.check_suffix file script_ext then
    on_script file
  else if Filename.check_suffix file js_ext then
    on_js file
  else
    raise (Sys_error (file ^ ": unrecognized file type"))


(* Output *)

let create_binary_file file _ get_module =
  trace ("Encoding (" ^ file ^ ")...");
  let s = Encode.encode (get_module ()) in
  let oc = open_out_bin file in
  try
    trace "Writing...";
    output_string oc s;
    close_out oc
  with exn -> close_out oc; raise exn

let create_sexpr_file file _ get_module =
  trace ("Writing (" ^ file ^ ")...");
  let oc = open_out file in
  try
    Print.module_ oc !Flags.width (get_module ());
    close_out oc
  with exn -> close_out oc; raise exn

let create_script_file mode file get_script _ =
  trace ("Writing (" ^ file ^ ")...");
  let oc = open_out file in
  try
    Print.script oc !Flags.width mode (get_script ());
    close_out oc
  with exn -> close_out oc; raise exn

let create_js_file file get_script _ =
  trace ("Converting (" ^ file ^ ")...");
  let js = Js.of_script (get_script ()) in
  let oc = open_out file in
  try
    trace "Writing...";
    output_string oc js;
    close_out oc
  with exn -> close_out oc; raise exn

let output_file =
  dispatch_file_ext
    create_binary_file
    create_sexpr_file
    (create_script_file `Binary)
    (create_script_file `Textual)
    create_js_file

let output_stdout get_module =
  trace "Printing...";
  Print.module_ stdout !Flags.width (get_module ())


(* Input *)

let error at category msg =
  trace ("Error: ");
  prerr_endline (Source.string_of_region at ^ ": " ^ category ^ ": " ^ msg);
  false

let input_from get_script run =
  try
    let script = get_script () in
    trace "Running...";
    run script;
    true
  with
  | Decode.Code (at, msg) -> error at "decoding error" msg
  | Parse.Syntax (at, msg) -> error at "syntax error" msg
  | Valid.Invalid (at, msg) -> error at "invalid module" msg
  | Import.Unknown (at, msg) -> error at "link failure" msg
  | Eval.Link (at, msg) -> error at "link failure" msg
  | Eval.Trap (at, msg) -> error at "runtime trap" msg
  | Eval.Exhaustion (at, msg) -> error at "resource exhaustion" msg
  | Eval.Crash (at, msg) -> error at "runtime crash" msg
  | Encode.Code (at, msg) -> error at "encoding error" msg
  | IO (at, msg) -> error at "i/o error" msg
  | Assert (at, msg) -> error at "assertion failure" msg
  | Abort _ -> false

let input_script start name lexbuf run =
  input_from (fun _ -> Parse.parse name lexbuf start) run

let input_sexpr name lexbuf run =
  input_from (fun _ ->
    let var_opt, def = Parse.parse name lexbuf Parse.Module in
    [Module (var_opt, def) @@ no_region]) run

let input_binary name buf run =
  let open Source in
  input_from (fun _ ->
    [Module (None, Encoded (name, buf) @@ no_region) @@ no_region]) run

let input_sexpr_file input file run =
  trace ("Loading (" ^ file ^ ")...");
  let ic = open_in file in
  try
    let lexbuf = Lexing.from_channel ic in
    trace "Parsing...";
    let success = input file lexbuf run in
    close_in ic;
    success
  with exn -> close_in ic; raise exn

let input_binary_file file run =
  trace ("Loading (" ^ file ^ ")...");
  let ic = open_in_bin file in
  try
    let len = in_channel_length ic in
    let buf = Bytes.make len '\x00' in
    really_input ic buf 0 len;
    trace "Decoding...";
    let success = input_binary file (Bytes.to_string buf) run in
    close_in ic;
    success
  with exn -> close_in ic; raise exn

let input_js_file file run =
  raise (Sys_error (file ^ ": unrecognized input file type"))

let input_file file run =
  dispatch_file_ext
    input_binary_file
    (input_sexpr_file input_sexpr)
    (input_sexpr_file (input_script Parse.Script))
    (input_sexpr_file (input_script Parse.Script))
    input_js_file
    file run

let input_string string run =
  trace ("Running (\"" ^ String.escaped string ^ "\")...");
  let lexbuf = Lexing.from_string string in
  trace "Parsing...";
  input_script Parse.Script "string" lexbuf run


(* Interactive *)

let continuing = ref false

let lexbuf_stdin buf len =
  let prompt = if !continuing then "  " else "> " in
  print_string prompt; flush_all ();
  continuing := true;
  let rec loop i =
    if i = len then i else
    let ch = input_char stdin in
    Bytes.set buf i ch;
    if ch = '\n' then i + 1 else loop (i + 1)
  in
  let n = loop 0 in
  if n = 1 then continuing := false else trace "Parsing...";
  n

let input_stdin run =
  let lexbuf = Lexing.from_function lexbuf_stdin in
  let rec loop () =
    let success = input_script Parse.Script1 "stdin" lexbuf run in
    if not success then Lexing.flush_input lexbuf;
    if Lexing.(lexbuf.lex_curr_pos >= lexbuf.lex_buffer_len - 1) then
      continuing := false;
    loop ()
  in
  try loop () with End_of_file ->
    print_endline "";
    trace "Bye."


(* Printing *)

let print_import m im =
  let open Types in
  let category, annotation =
    match Ast.import_type m im with
    | ExternFuncType t -> "func", string_of_func_type t
    | ExternTableType t -> "table", string_of_table_type t
    | ExternMemoryType t -> "memory", string_of_memory_type t
    | ExternGlobalType t -> "global", string_of_global_type t
  in
  Printf.printf "  import %s \"%s\" \"%s\" : %s\n"
    category (Ast.string_of_name im.it.Ast.module_name)
      (Ast.string_of_name im.it.Ast.item_name) annotation

let print_export m ex =
  let open Types in
  let category, annotation =
    match Ast.export_type m ex with
    | ExternFuncType t -> "func", string_of_func_type t
    | ExternTableType t -> "table", string_of_table_type t
    | ExternMemoryType t -> "memory", string_of_memory_type t
    | ExternGlobalType t -> "global", string_of_global_type t
  in
  Printf.printf "  export %s \"%s\" : %s\n"
    category (Ast.string_of_name ex.it.Ast.name) annotation

let print_module x_opt m =
  Printf.printf "module%s :\n"
    (match x_opt with None -> "" | Some x -> " " ^ x.it);
  List.iter (print_import m) m.it.Ast.imports;
  List.iter (print_export m) m.it.Ast.exports;
  flush_all ()

let print_values vs =
  let ts = List.map Values.type_of vs in
  Printf.printf "%s : %s\n"
    (Values.string_of_values vs) (Types.string_of_value_types ts);
  flush_all ()

let string_of_nan = function
  | CanonicalNan -> "nan:canonical"
  | ArithmeticNan -> "nan:arithmetic"

let rec type_of_result r =
  match r.it with
  | LitResult v -> Some (Values.type_of v.it)
  | NanResult n -> Some (Values.type_of n.it)
  | EitherResult rs ->
    let ts = List.map type_of_result rs in
    List.fold_left (fun t1 t2 -> if t1 = t2 then t1 else None) (List.hd ts) ts

let rec string_of_result r =
  match r.it with
  | LitResult v -> Values.string_of_value v.it
  | NanResult nanop ->
    (match nanop.it with
    | Values.I32 _ | Values.I64 _ -> assert false
    | Values.F32 n | Values.F64 n -> string_of_nan n
    )
  | EitherResult rs ->
    "(" ^ String.concat " | " (List.map string_of_result rs) ^ ")"

let string_of_results = function
  | [r] -> string_of_result r
  | rs -> "[" ^ String.concat " " (List.map string_of_result rs) ^ "]"

let string_of_value_type_opt = function
  | Some t -> Types.string_of_value_type t
  | None -> "?"

let string_of_value_type_opts = function
  | [t] -> string_of_value_type_opt t
  | ts -> "[" ^ String.concat " " (List.map string_of_value_type_opt ts) ^ "]"

let print_results rs =
  let ts = List.map type_of_result rs in
  Printf.printf "%s : %s\n"
    (string_of_results rs) (string_of_value_type_opts ts);
  flush_all ()


(* Tasks & contexts *)

module Map = Map.Make(String)

type task =
{
  context : context;
  script : script ref;
}

and context =
{
  scripts : script Map.t ref;
  threads : task Map.t ref;
  modules : Ast.module_ Map.t ref;
  instances : Instance.module_inst Map.t ref;
  registry : Instance.module_inst Map.t ref;
  tasks : task list ref;
  config : Eval.config ref;
  thread : Eval.thread_id;
}

let context_for config thread =
  { scripts = ref Map.empty;
    threads = ref Map.empty;
    modules = ref Map.empty;
    instances = ref Map.empty;
    registry = ref Map.empty;
    tasks = ref [];
    config;
    thread;
  }

let context () =
  let t, ec = Eval.spawn Eval.empty_config in
  context_for (ref ec) t

let local c =
  {(context_for c.config c.thread) with tasks = c.tasks}

let bind map x_opt y =
  let map' =
    match x_opt with
    | None -> !map
    | Some x -> Map.add x.it y !map
  in map := Map.add "" y map'

let lookup category map x_opt at =
  let key = match x_opt with None -> "" | Some x -> x.it in
  try Map.find key !map with Not_found ->
    IO.error at
      (if key = "" then "no " ^ category ^ " defined"
       else "unknown " ^ category ^ " " ^ key)

let lookup_script c = lookup "script" c.scripts
let lookup_thread c = lookup "thread" c.threads
let lookup_module c = lookup "module" c.modules
let lookup_instance c = lookup "module" c.instances

let lookup_registry c module_name item_name _t =
  match Instance.export (Map.find module_name !(c.registry)) item_name with
  | Some ext -> ext
  | None -> raise Not_found


(* Running *)

let rec run_definition c def : Ast.module_ =
  match def.it with
  | Textual m -> m
  | Encoded (name, bs) ->
    trace "Decoding...";
    Decode.decode name bs
  | Quoted (_, s) ->
    trace "Parsing quote...";
    let def' = Parse.string_to_module s in
    run_definition c def'

let run_action c act : Values.value list option =
  match act.it with
  | Invoke (x_opt, name, args) ->
    trace ("Invoking function \"" ^ Ast.string_of_name name ^ "\"...");
    let inst = lookup_instance c x_opt act.at in
    (match Instance.export inst name with
    | Some (Instance.ExternFunc f) ->
      let vs = List.map (fun v -> v.it) args in
      c.config := Eval.invoke !(c.config) c.thread f vs;
      None
    | Some _ -> Assert.error act.at "export is not a function"
    | None -> Assert.error act.at "undefined export"
    )

  | Get (x_opt, name) ->
    trace ("Getting global \"" ^ Ast.string_of_name name ^ "\"...");
    let inst = lookup_instance c x_opt act.at in
    (match Instance.export inst name with
    | Some (Instance.ExternGlobal gl) -> Some [Global.load gl]
    | Some _ -> Assert.error act.at "export is not a global"
    | None -> Assert.error act.at "undefined export"
    )

  | Eval ->
    match Eval.status !(c.config) c.thread with
    | Eval.Running ->
      (try c.config := Eval.step !(c.config) c.thread
      with exn -> c.config := Eval.clear !(c.config) c.thread; raise exn);
      None
    | Eval.Result vs ->
      c.config := Eval.clear !(c.config) c.thread;
      Some vs
    | Eval.Trap exn ->
      c.config := Eval.clear !(c.config) c.thread;
      raise exn

let rec match_result at v r =
  let open Values in
  match r.it with
  | LitResult v' -> v = v'.it
  | NanResult nanop ->
    (match nanop.it, v with
    | F32 CanonicalNan, F32 z -> z = F32.pos_nan || z = F32.neg_nan
    | F64 CanonicalNan, F64 z -> z = F64.pos_nan || z = F64.neg_nan
    | F32 ArithmeticNan, F32 z ->
      let pos_nan = F32.to_bits F32.pos_nan in
      Int32.logand (F32.to_bits z) pos_nan = pos_nan
    | F64 ArithmeticNan, F64 z ->
      let pos_nan = F64.to_bits F64.pos_nan in
      Int64.logand (F64.to_bits z) pos_nan = pos_nan
    | _, _ -> false
    )
  | EitherResult rs -> List.exists (match_result at v) rs

let assert_result at got expect =
  if
    List.length got <> List.length expect ||
    not (List.for_all2 (match_result at) got expect)
  then begin
    print_string "Result: "; print_values got;
    print_string "Expect: "; print_results expect;
    Assert.error at "wrong return values"
  end

let assert_message at name msg re =
  if
    String.length msg < String.length re ||
    String.sub msg 0 (String.length re) <> re
  then begin
    print_endline ("Result: \"" ^ msg ^ "\"");
    print_endline ("Expect: \"" ^ re ^ "\"");
    Assert.error at ("wrong " ^ name ^ " error")
  end

let run_assertion c ass : assertion option =
  match ass.it with
  | AssertMalformed (def, re) ->
    trace "Asserting malformed...";
    (match ignore (run_definition c def) with
    | exception Decode.Code (_, msg) ->
      assert_message ass.at "decoding" msg re; None
    | exception Parse.Syntax (_, msg) ->
      assert_message ass.at "parsing" msg re; None
    | () -> Assert.error ass.at "expected decoding/parsing error"
    )

  | AssertInvalid (def, re) ->
    trace "Asserting invalid...";
    (match
      let m = run_definition c def in
      Valid.check_module m
    with
    | exception Valid.Invalid (_, msg) ->
      assert_message ass.at "validation" msg re; None
    | () -> Assert.error ass.at "expected validation error"
    )

  | AssertUnlinkable (def, re) ->
    trace "Asserting unlinkable...";
    let m = run_definition c def in
    if not !Flags.unchecked then Valid.check_module m;
    (match
      let imports = Import.link m in
      c.config := snd (Eval.init !(c.config) c.thread m imports)
    with
    | exception (Import.Unknown (_, msg) | Eval.Link (_, msg)) ->
      assert_message ass.at "linking" msg re; None
    | () -> Assert.error ass.at "expected linking error"
    )

  | AssertUninstantiable (def, re) ->
    trace "Asserting trap...";
    let m = run_definition c def in
    if not !Flags.unchecked then Valid.check_module m;
    let imports = Import.link m in
    c.config := snd (Eval.init !(c.config) c.thread m imports);
    Some (AssertTrap (Eval @@ ass.at, re) @@ ass.at)

  | AssertReturn (act, rs) ->
    if act.it <> Eval then trace ("Asserting return...");
    (match run_action c act with
    | None -> Some (AssertReturn (Eval @@ ass.at, rs) @@ ass.at)
    | Some got_vs -> assert_result ass.at got_vs rs; None
    )

  | AssertTrap (act, re) ->
    if act.it <> Eval then trace ("Asserting trap...");
    (match run_action c act with
    | None -> Some (AssertTrap (Eval @@ ass.at, re) @@ ass.at)
    | exception Eval.Trap (_, msg) ->
      assert_message ass.at "runtime" msg re; None
    | Some _ -> Assert.error ass.at "expected runtime error"
    )

  | AssertExhaustion (act, re) ->
    if act.it <> Eval then trace ("Asserting exhaustion...");
    (match run_action c act with
    | None -> Some (AssertExhaustion (Eval @@ ass.at, re) @@ ass.at)
    | exception Eval.Exhaustion (_, msg) ->
      assert_message ass.at "exhaustion" msg re; None
    | Some _ -> Assert.error ass.at "expected exhaustion error"
    )

let rec run_command c cmd : command list =
  match cmd.it with
  | Module (x_opt, def) ->
    let m = run_definition c def in
    if not !Flags.unchecked then begin
      trace "Checking...";
      Valid.check_module m;
      if !Flags.print_sig then begin
        trace "Signature:";
        print_module x_opt m
      end
    end;
    bind c.scripts x_opt [cmd];
    bind c.modules x_opt m;
    if !Flags.dry then [] else begin
      trace "Initializing...";
      let imports = Import.link m in
      let inst, config' = Eval.init !(c.config) c.thread m imports in
      bind c.instances x_opt inst;
      c.config := config';
      [Action (Eval @@ cmd.at) @@ cmd.at]
    end

  | Register (name, x_opt) ->
    if !Flags.dry then [] else begin
      trace ("Registering module \"" ^ Ast.string_of_name name ^ "\"...");
      let inst = lookup_instance c x_opt cmd.at in
      c.registry := Map.add (Utf8.encode name) inst !(c.registry);
      Import.register name (lookup_registry c (Utf8.encode name));
      []
    end

  | Action act ->
    if !Flags.dry then [] else begin
      match run_action c act with
      | None -> [Action (Eval @@ cmd.at) @@ cmd.at]
      | Some vs -> if vs <> [] then print_values vs; []
    end

  | Assertion ass ->
    if !Flags.dry then [] else begin
      match run_assertion c ass with
      | None -> []
      | Some ass' -> [Assertion ass' @@ cmd.at]
    end

  | Thread (x_opt, xs, cmds) ->
    let thread, config' = Eval.spawn !(c.config) in
    let task = {context = {(local c) with thread}; script = ref cmds} in
    List.iter (fun x ->
      if not !Flags.dry then begin
      let inst = lookup_instance c (Some x) x.at in
        if Instance.shared_module inst <> Types.Shared then
          IO.error x.at ("module " ^ x.it ^ " is not sharable");
        bind task.context.instances (Some x) inst
      end;
      bind task.context.modules (Some x) (lookup_module c (Some x) cmd.at)
    ) xs;
    c.config := config';
    c.tasks := task :: !(c.tasks);
    bind c.threads x_opt task;
    []

  | Wait x_opt ->
    let task = lookup_thread c x_opt cmd.at in
    if !(task.script) = [] then
      []
    else
      [Wait x_opt @@ cmd.at]

  | Meta cmd ->
    List.map (fun m -> Meta m @@ cmd.at) (run_meta c cmd)

and run_meta c cmd : meta list =
  match cmd.it with
  | Script (x_opt, [], [], quote) ->
    bind c.scripts x_opt (List.rev quote);
    []

  | Script (x_opt, [], cmd::cmds, quote) ->
    let quote' = quote_command cmd in
    [Script (x_opt, [cmd], cmds, quote' @ quote) @@ cmd.at]

  | Script (x_opt, cmd::cmds1, cmds2, quote) ->
    let cmds' = run_command c cmd in
    [Script (x_opt, cmds' @ cmds1, cmds2, quote) @@ cmd.at]

  | Input (x_opt, file) ->
    let script = ref [] in
    (try if not (input_file file ((:=) script)) then
      Abort.error cmd.at "aborting"
    with Sys_error msg -> IO.error cmd.at msg);
    (match !script with
    | [{it = Module (None, def); at}] -> script := [Module (x_opt, def) @@ at]
    | _ -> ()
    );
    [Script (x_opt, [], !script, []) @@ cmd.at]

  | Output (x_opt, Some file) ->
    (try
      output_file file
        (fun () -> lookup_script c x_opt cmd.at)
        (fun () -> lookup_module c x_opt cmd.at)
    with Sys_error msg -> IO.error cmd.at msg);
    []

  | Output (x_opt, None) ->
    (try output_stdout (fun () -> lookup_module c x_opt cmd.at)
    with Sys_error msg -> IO.error cmd.at msg);
    []

and quote_command cmd : command list =
  match cmd.it with
  | Module _ | Register _ | Action _ | Assertion _ | Thread _ | Wait _ -> [cmd]
  | Meta meta -> quote_meta meta

and quote_meta cmd : command list =
  match cmd.it with
  | Script (_, [], [], quote) -> quote
  | Script _ | Input _ | Output _ -> []

let run_script c script =
  let task = {context = c; script = ref script} in
  c.tasks := task :: !(c.tasks);
  while !(task.script) <> [] do
    let task' = List.nth !(c.tasks) (Random.int (List.length !(c.tasks))) in
    match !(task'.script) with
    | [] -> ()
    | cmd::cmds -> task'.script := run_command task'.context cmd @ cmds
  done

let run_file c file = input_file file (run_script c)
let run_string c string = input_string string (run_script c)
let run_stdin c = input_stdin (run_script c)
