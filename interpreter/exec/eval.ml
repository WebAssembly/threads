open Values
open Types
open Instance
open Ast
open Source


(* Errors *)

module Link = Error.Make ()
module Trap = Error.Make ()
module Crash = Error.Make ()
module Exhaustion = Error.Make ()

exception Link = Link.Error
exception Trap = Trap.Error
exception Crash = Crash.Error (* failure that cannot happen in valid code *)
exception Exhaustion = Exhaustion.Error

let memory_error at = function
  | Memory.Bounds -> "out of bounds memory access"
  | Memory.SizeOverflow -> "memory size overflow"
  | Memory.SizeLimit -> "memory size limit reached"
  | Memory.Type -> Crash.error at "type mismatch at memory access"
  | exn -> raise exn

let numeric_error at = function
  | Numeric_error.IntegerOverflow -> "integer overflow"
  | Numeric_error.IntegerDivideByZero -> "integer divide by zero"
  | Numeric_error.InvalidConversionToInteger -> "invalid conversion to integer"
  | Eval_numeric.TypeError (i, v, t) ->
    Crash.error at
      ("type error, expected " ^ Types.string_of_value_type t ^ " as operand " ^
       string_of_int i ^ ", got " ^ Types.string_of_value_type (type_of v))
  | exn -> raise exn

(* Must be positive and non-zero *)
let timeout_epsilon = 1000000L


(* Administrative Expressions & Configurations *)

type 'a stack = 'a list

type frame =
{
  inst : module_inst;
  locals : value ref list;
}

type code = value stack * admin_instr list

and admin_instr = admin_instr' phrase
and admin_instr' =
  | Plain of instr'
  | Invoke of func_inst
  | Trapping of string
  | Returning of value stack
  | Breaking of int32 * value stack
  | Label of int32 * instr list * code
  | Frame of int32 * frame * code
  | Suspend of memory_inst * Memory.address * float

type action =
  | NoAction
    (* memory, cell index, number of threads to wake *)
  | NotifyAction of memory_inst * Memory.address * I32.t

type thread =
{
  frame : frame;
  code : code;
  budget : int;  (* to model stack overflow *)
}

type config = thread list
type thread_id = int
type status = Running | Result of value list | Trap of exn

let frame inst locals = {inst; locals}
let thread inst vs es = {frame = frame inst []; code = vs, es; budget = 300}
let empty_thread = thread empty_module_inst [] []
let empty_config = []
let spawn (c : config) = List.length c, c @ [empty_thread]

let status (c : config) (n : thread_id) : status =
  let t = List.nth c n in
  match t.code with
  | vs, [] -> Result (List.rev vs)
  | [], {it = Trapping msg; at} :: _ -> Trap (Trap.Error (at, msg))
  | _ -> Running

let clear (c : config) (n : thread_id) : config =
  let ts1, t, ts2 = Lib.List.extract n c in
  ts1 @ [{t with code = [], []}] @ ts2


let plain e = Plain e.it @@ e.at

let lookup category list x =
  try Lib.List32.nth list x.it with Failure _ ->
    Crash.error x.at ("undefined " ^ category ^ " " ^ Int32.to_string x.it)

let type_ (inst : module_inst) x = lookup "type" inst.types x
let func (inst : module_inst) x = lookup "function" inst.funcs x
let table (inst : module_inst) x = lookup "table" inst.tables x
let memory (inst : module_inst) x = lookup "memory" inst.memories x
let global (inst : module_inst) x = lookup "global" inst.globals x
let local (frame : frame) x = lookup "local" frame.locals x

let elem inst x i at =
  match Table.load (table inst x) i with
  | Table.Uninitialized ->
    Trap.error at ("uninitialized element " ^ Int32.to_string i)
  | f -> f
  | exception Table.Bounds ->
    Trap.error at ("undefined element " ^ Int32.to_string i)

let func_elem inst x i at =
  match elem inst x i at with
  | FuncElem f -> f
  | _ -> Crash.error at ("type mismatch for element " ^ Int32.to_string i)

let func_type_of = function
  | Func.AstFunc (t, inst, f) -> t
  | Func.HostFunc (t, _) -> t

let block_type inst bt =
  match bt with
  | VarBlockType x -> type_ inst x
  | ValBlockType None -> FuncType ([], [])
  | ValBlockType (Some t) -> FuncType ([], [t])

let take n (vs : 'a stack) at =
  try Lib.List32.take n vs with Failure _ -> Crash.error at "stack underflow"

let drop n (vs : 'a stack) at =
  try Lib.List32.drop n vs with Failure _ -> Crash.error at "stack underflow"

let check_align addr ty sz at =
  if not (Memory.is_aligned addr ty sz) then
    Trap.error at "unaligned atomic memory access"

let check_shared mem at =
  if shared_memory_type (Memory.type_of mem) <> Shared then
    Trap.error at "expected shared memory"


(* Evaluation *)

(*
 * Conventions:
 *   e  : instr
 *   v  : value
 *   es : instr list
 *   vs : value stack
 *   t : thread
 *   c : config
 *)

let rec step_thread (t : thread) : thread * action =
  let {frame; code = vs, es; _} = t in
  let e = List.hd es in
  let vs', es', act =
    match e.it, vs with
    | Plain e', vs ->
      (match e', vs with
      | Unreachable, vs ->
        vs, [Trapping "unreachable executed" @@ e.at], NoAction

      | Nop, vs ->
        vs, [], NoAction

      | Block (bt, es'), vs ->
        let FuncType (ts1, ts2) = block_type frame.inst bt in
        let n1 = Lib.List32.length ts1 in
        let n2 = Lib.List32.length ts2 in
        let args, vs' = take n1 vs e.at, drop n1 vs e.at in
        vs', [Label (n2, [], (args, List.map plain es')) @@ e.at], NoAction

      | Loop (bt, es'), vs ->
        let FuncType (ts1, ts2) = block_type frame.inst bt in
        let n1 = Lib.List32.length ts1 in
        let args, vs' = take n1 vs e.at, drop n1 vs e.at in
        vs', [Label (n1, [e' @@ e.at], (args, List.map plain es')) @@ e.at], NoAction

      | If (bt, es1, es2), I32 0l :: vs' ->
        vs', [Plain (Block (bt, es2)) @@ e.at], NoAction

      | If (bt, es1, es2), I32 i :: vs' ->
        vs', [Plain (Block (bt, es1)) @@ e.at], NoAction

      | Br x, vs ->
        [], [Breaking (x.it, vs) @@ e.at], NoAction

      | BrIf x, I32 0l :: vs' ->
        vs', [], NoAction

      | BrIf x, I32 i :: vs' ->
        vs', [Plain (Br x) @@ e.at], NoAction

      | BrTable (xs, x), I32 i :: vs' when I32.ge_u i (Lib.List32.length xs) ->
        vs', [Plain (Br x) @@ e.at], NoAction

      | BrTable (xs, x), I32 i :: vs' ->
        vs', [Plain (Br (Lib.List32.nth xs i)) @@ e.at], NoAction

      | Return, vs ->
        [], [Returning vs @@ e.at], NoAction

      | Call x, vs ->
        vs, [Invoke (func frame.inst x) @@ e.at], NoAction

      | CallIndirect x, I32 i :: vs ->
        let func = func_elem frame.inst (0l @@ e.at) i e.at in
        if type_ frame.inst x <> Func.type_of func then
          vs, [Trapping "indirect call type mismatch" @@ e.at], NoAction
        else
          vs, [Invoke func @@ e.at], NoAction

      | Drop, v :: vs' ->
        vs', [], NoAction

      | Select, I32 0l :: v2 :: v1 :: vs' ->
        v2 :: vs', [], NoAction

      | Select, I32 i :: v2 :: v1 :: vs' ->
        v1 :: vs', [], NoAction

      | LocalGet x, vs ->
        !(local frame x) :: vs, [], NoAction

      | LocalSet x, v :: vs' ->
        local frame x := v;
        vs', [], NoAction

      | LocalTee x, v :: vs' ->
        local frame x := v;
        v :: vs', [], NoAction

      | GlobalGet x, vs ->
        Global.load (global frame.inst x) :: vs, [], NoAction

      | GlobalSet x, v :: vs' ->
        (try Global.store (global frame.inst x) v; vs', [], NoAction
        with Global.NotMutable -> Crash.error e.at "write to immutable global"
           | Global.Type -> Crash.error e.at "type mismatch at global write")

      | Load {offset; ty; sz; _}, I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          let v =
            match sz with
            | None -> Memory.load_value mem addr offset ty
            | Some (sz, ext) -> Memory.load_packed sz ext mem addr offset ty
          in v :: vs', [], NoAction
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction)

      | Store {offset; sz; _}, v :: I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          (match sz with
          | None -> Memory.store_value mem addr offset v
          | Some sz -> Memory.store_packed sz mem addr offset v
          );
          vs', [], NoAction
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction);

      | AtomicLoad {offset; ty; sz; _}, I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          check_align addr ty sz e.at;
          let v =
            match sz with
            | None -> Memory.load_value mem addr offset ty
            | Some sz -> Memory.load_packed sz ZX mem addr offset ty
          in v :: vs', [], NoAction
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction)

      | AtomicStore {offset; ty; sz; _}, v :: I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          check_align addr ty sz e.at;
          (match sz with
          | None -> Memory.store_value mem addr offset v
          | Some sz -> Memory.store_packed sz mem addr offset v
          );
          vs', [], NoAction
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction);

      | AtomicRmw (rmwop, {offset; ty; sz; _}), v :: I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          check_align addr ty sz e.at;
          let v1 =
            match sz with
            | None -> Memory.load_value mem addr offset ty
            | Some sz -> Memory.load_packed sz ZX mem addr offset ty
          in let v2 = Eval_numeric.eval_rmwop rmwop v1 v
          in (match sz with
          | None -> Memory.store_value mem addr offset v2
          | Some sz -> Memory.store_packed sz mem addr offset v2
          );
          v1 :: vs', [], NoAction
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction)

      | AtomicRmwCmpXchg {offset; ty; sz; _}, vn :: ve :: I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          check_align addr ty sz e.at;
          let v1 =
            match sz with
            | None -> Memory.load_value mem addr offset ty
            | Some sz -> Memory.load_packed sz ZX mem addr offset ty
          in (if v1 = ve then
                match sz with
                | None -> Memory.store_value mem addr offset vn
                | Some sz -> Memory.store_packed sz mem addr offset vn
          );
          v1 :: vs', [], NoAction
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction);

      | MemoryAtomicWait {offset; ty; sz; _}, I64 timeout :: ve :: I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          assert (sz = None);
          check_align addr ty sz e.at;
          check_shared mem e.at;
          let v = Memory.load_value mem addr offset ty in
          if v = ve then
            if timeout >= 0L && timeout < timeout_epsilon then
              I32 2l :: vs', [], NoAction (* Treat as though wait timed out immediately *)
            else
              (* TODO: meaningful timestamp handling *)
              vs', [Suspend (mem, addr, 0.) @@ e.at], NoAction
          else
            I32 1l :: vs', [], NoAction  (* Not equal *)
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction)

      | MemoryAtomicNotify {offset; ty; sz; _}, I32 count :: I32 i :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let addr = I64_convert.extend_i32_u i in
        (try
          check_align addr ty sz e.at;
          let _ = Memory.load_value mem addr offset ty in
          if count = 0l then
            I32 0l :: vs', [], NoAction  (* Trivial case waking 0 waiters *)
          else
            vs', [], NotifyAction (mem, addr, count)
        with exn -> vs', [Trapping (memory_error e.at exn) @@ e.at], NoAction)

      | AtomicFence, vs ->
        vs, [], NoAction

      | MemorySize, vs ->
        let mem = memory frame.inst (0l @@ e.at) in
        I32 (Memory.size mem) :: vs, [], NoAction

      | MemoryGrow, I32 delta :: vs' ->
        let mem = memory frame.inst (0l @@ e.at) in
        let old_size = Memory.size mem in
        let result =
          try Memory.grow mem delta; old_size
          with Memory.SizeOverflow | Memory.SizeLimit | Memory.OutOfMemory -> -1l
        in I32 result :: vs', [], NoAction

      | Const v, vs ->
        v.it :: vs, [], NoAction

      | Test testop, v :: vs' ->
        (try value_of_bool (Eval_numeric.eval_testop testop v) :: vs', [], NoAction
        with exn -> vs', [Trapping (numeric_error e.at exn) @@ e.at], NoAction)

      | Compare relop, v2 :: v1 :: vs' ->
        (try value_of_bool (Eval_numeric.eval_relop relop v1 v2) :: vs', [], NoAction
        with exn -> vs', [Trapping (numeric_error e.at exn) @@ e.at], NoAction)

      | Unary unop, v :: vs' ->
        (try Eval_numeric.eval_unop unop v :: vs', [], NoAction
        with exn -> vs', [Trapping (numeric_error e.at exn) @@ e.at], NoAction)

      | Binary binop, v2 :: v1 :: vs' ->
        (try Eval_numeric.eval_binop binop v1 v2 :: vs', [], NoAction
        with exn -> vs', [Trapping (numeric_error e.at exn) @@ e.at], NoAction)

      | Convert cvtop, v :: vs' ->
        (try Eval_numeric.eval_cvtop cvtop v :: vs', [], NoAction
        with exn -> vs', [Trapping (numeric_error e.at exn) @@ e.at], NoAction)

      | _ ->
        let s1 = string_of_values (List.rev vs) in
        let s2 = string_of_value_types (List.map type_of (List.rev vs)) in
        Crash.error e.at
          ("missing or ill-typed operand on stack (" ^ s1 ^ " : " ^ s2 ^ ")")
      )

    | Trapping msg, vs ->
      [], [Trapping msg @@ e.at], NoAction

    | Returning vs', vs ->
      Crash.error e.at "undefined frame"

    | Breaking (k, vs'), vs ->
      Crash.error e.at "undefined label"

    | Label (n, es0, (vs', [])), vs ->
      vs' @ vs, [], NoAction

    | Label (n, es0, (vs', {it = Trapping msg; at} :: es')), vs ->
      vs, [Trapping msg @@ at], NoAction

    | Label (n, es0, (vs', {it = Returning vs0; at} :: es')), vs ->
      vs, [Returning vs0 @@ at], NoAction

    | Label (n, es0, (vs', {it = Breaking (0l, vs0); at} :: es')), vs ->
      take n vs0 e.at @ vs, List.map plain es0, NoAction

    | Label (n, es0, (vs', {it = Breaking (k, vs0); at} :: es')), vs ->
      vs, [Breaking (Int32.sub k 1l, vs0) @@ at], NoAction

    | Label (n, es0, code'), vs ->
      let t', act = step_thread {t with code = code'} in
      vs, [Label (n, es0, t'.code) @@ e.at], act

    | Frame (n, frame', (vs', [])), vs ->
      vs' @ vs, [], NoAction

    | Frame (n, frame', (vs', {it = Trapping msg; at} :: es')), vs ->
      vs, [Trapping msg @@ at], NoAction

    | Frame (n, frame', (vs', {it = Returning vs0; at} :: es')), vs ->
      take n vs0 e.at @ vs, [], NoAction

    | Frame (n, frame', code'), vs ->
      let t', act = step_thread {frame = frame'; code = code'; budget = t.budget - 1} in
      vs, [Frame (n, t'.frame, t'.code) @@ e.at], act

    | Invoke func, vs when t.budget = 0 ->
      Exhaustion.error e.at "call stack exhausted"

    | Invoke func, vs ->
      let FuncType (ins, out) = func_type_of func in
      let n1, n2 = Lib.List32.length ins, Lib.List32.length out in
      let args, vs' = take n1 vs e.at, drop n1 vs e.at in
      (match func with
      | Func.AstFunc (t, inst', f) ->
        let locals' = List.rev args @ List.map default_value f.it.locals in
        let frame' = {inst = !inst'; locals = List.map ref locals'} in
        let instr' = [Label (n2, [], ([], List.map plain f.it.body)) @@ f.at] in
        vs', [Frame (n2, frame', ([], instr')) @@ e.at], NoAction

      | Func.HostFunc (t, f) ->
        try List.rev (f (List.rev args)) @ vs', [], NoAction
        with Crash (_, msg) -> Crash.error e.at msg
      )

    | Suspend _, vs ->
      (* TODO: meaningful timestamp handling *)
      vs, [e], NoAction

  in {t with code = vs', es' @ List.tl es}, act

let rec plug_value (c : code) (v : value) : code =
  let vs, es = c in
  match es with
  | {it = Label (n, es0, c'); at} :: es' ->
    vs, {it = Label (n, es0, plug_value c' v); at} :: es'
  | {it = Frame (n, f, c'); at} :: es' ->
    vs, {it = Frame (n, f, plug_value c' v); at} :: es'
  | _ ->
    v :: vs, es

let rec try_unsuspend (c : code) (m : memory_inst) (addr : Memory.address) : code option =
  let vs, es = c in
  match es with
  | {it = Label (n, es0, c'); at} :: es' ->
    Lib.Option.map (fun c'' -> vs, {it = Label (n, es0, c''); at} :: es') (try_unsuspend c' m addr)
  | {it = Frame (n, f, c'); at} :: es' ->
    Lib.Option.map (fun c'' -> vs, {it = Frame (n, f, c''); at} :: es') (try_unsuspend c' m addr)
  | {it = Suspend (m', addr', timeout); at} :: es' ->
    if m == m' && addr = addr' then
      Some (I32 0l :: vs, es')
    else
      None
  | _ ->
    None

let rec wake (c : config) (m : memory_inst) (addr : Memory.address) (count : int32) : config * int32 =
  if count = 0l then
    c, 0l
  else
    match c with
    | [] ->
      c, 0l
    | t :: ts ->
      let t', count' = match (try_unsuspend t.code m addr) with | None -> t, 0l | Some c' -> {t with code = c'}, 1l in
      let ts', count'' = wake ts m addr (Int32.sub count count') in
      t' :: ts', Int32.add count' count''

let rec step (c : config) (n : thread_id) : config =
  let ts1, t, ts2 = Lib.List.extract n c in
  if snd t.code = [] then
    step c n
  else
    let t', act = try step_thread t with Stack_overflow ->
      Exhaustion.error (List.hd (snd t.code)).at "call stack exhausted"
    in
    match act with
    | NotifyAction (m, addr, count) ->
      let ts1', count1 = wake ts1 m addr count in
      let ts2', count2 = wake ts2 m addr (Int32.sub count count1) in
      ts1' @ [{t' with code = plug_value t'.code (I32 (Int32.add count1 count2))}] @ ts2'
    | _ -> ts1 @ [t'] @ ts2

let rec eval (c : config ref) (n : thread_id) : value list =
  match status !c n with
  | Result vs -> vs
  | Trap e -> raise e
  | Running ->
    let c' = step !c n in
    c := c'; eval c n


(* Functions & Constants *)

let invoke c n (func : func_inst) (vs : value list) : config =
  let at = match func with Func.AstFunc (_,_, f) -> f.at | _ -> no_region in
  let FuncType (ins, out) = Func.type_of func in
  if List.map Values.type_of vs <> ins then
    Crash.error at "wrong number or types of arguments";
  let ts1, t, ts2 = Lib.List.extract n c in
  let vs', es' = t.code in
  let code = List.rev vs @ vs', (Invoke func @@ at) :: es' in
  ts1 @ [{t with code}] @ ts2

let eval_const (inst : module_inst) (const : const) : value =
  let t = thread inst [] (List.map plain const.it) in
  match eval (ref [t]) 0 with
  | [v] -> v
  | _ -> Crash.error const.at "wrong number of results on stack"

let i32 (v : value) at =
  match v with
  | I32 i -> i
  | _ -> Crash.error at "type error: i32 value expected"


(* Modules *)

let create_func (inst : module_inst) (f : func) : func_inst =
  Func.alloc (type_ inst f.it.ftype) (ref inst) f

let create_table (inst : module_inst) (tab : table) : table_inst =
  let {ttype} = tab.it in
  Table.alloc ttype

let create_memory (inst : module_inst) (mem : memory) : memory_inst =
  let {mtype} = mem.it in
  Memory.alloc mtype

let create_global (inst : module_inst) (glob : global) : global_inst =
  let {gtype; value} = glob.it in
  let v = eval_const inst value in
  Global.alloc gtype v

let create_export (inst : module_inst) (ex : export) : export_inst =
  let {name; edesc} = ex.it in
  let ext =
    match edesc.it with
    | FuncExport x -> ExternFunc (func inst x)
    | TableExport x -> ExternTable (table inst x)
    | MemoryExport x -> ExternMemory (memory inst x)
    | GlobalExport x -> ExternGlobal (global inst x)
  in name, ext


let init_func (inst : module_inst) (func : func_inst) =
  match func with
  | Func.AstFunc (_, inst_ref, _) -> inst_ref := inst
  | _ -> assert false

let init_table (inst : module_inst) (seg : table_segment) =
  let {index; offset = const; init} = seg.it in
  let tab = table inst index in
  let offset = i32 (eval_const inst const) const.at in
  let end_ = Int32.(add offset (of_int (List.length init))) in
  let bound = Table.size tab in
  if I32.lt_u bound end_ || I32.lt_u end_ offset then
    Link.error seg.at "elements segment does not fit table";
  fun () ->
    Table.blit tab offset (List.map (fun x -> FuncElem (func inst x)) init)

let init_memory (inst : module_inst) (seg : memory_segment) =
  let {index; offset = const; init} = seg.it in
  let mem = memory inst index in
  let offset' = i32 (eval_const inst const) const.at in
  let offset = I64_convert.extend_i32_u offset' in
  let end_ = Int64.(add offset (of_int (String.length init))) in
  let bound = Memory.bound mem in
  if I64.lt_u bound end_ || I64.lt_u end_ offset then
    Link.error seg.at "data segment does not fit memory";
  fun () -> Memory.store_bytes mem offset init


let add_import (m : module_) (ext : extern) (im : import) (inst : module_inst)
  : module_inst =
  if not (match_extern_type (extern_type_of ext) (import_type m im)) then
    Link.error im.at "incompatible import type";
  match ext with
  | ExternFunc func -> {inst with funcs = func :: inst.funcs}
  | ExternTable tab -> {inst with tables = tab :: inst.tables}
  | ExternMemory mem -> {inst with memories = mem :: inst.memories}
  | ExternGlobal glob -> {inst with globals = glob :: inst.globals}

let init c n (m : module_) (exts : extern list) : module_inst * config =
  let
    { imports; tables; memories; globals; funcs; types;
      exports; elems; data; start
    } = m.it
  in
  if List.length exts <> List.length imports then
    Link.error m.at "wrong number of imports provided for initialisation";
  let inst0 =
    { (List.fold_right2 (add_import m) exts imports empty_module_inst) with
      types = List.map (fun type_ -> type_.it) types }
  in
  let fs = List.map (create_func inst0) funcs in
  let inst1 =
    { inst0 with
      funcs = inst0.funcs @ fs;
      tables = inst0.tables @ List.map (create_table inst0) tables;
      memories = inst0.memories @ List.map (create_memory inst0) memories;
      globals = inst0.globals @ List.map (create_global inst0) globals;
    }
  in
  let inst = {inst1 with exports = List.map (create_export inst1) exports} in
  List.iter (init_func inst) fs;
  let init_elems = List.map (init_table inst) elems in
  let init_datas = List.map (init_memory inst) data in
  List.iter (fun f -> f ()) init_elems;
  List.iter (fun f -> f ()) init_datas;
  let c' = Lib.Option.fold c (fun x -> invoke c n (func inst x) []) start in
  inst, c'
