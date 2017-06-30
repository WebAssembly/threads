# Import/Export mutable globals proposal

This page describes a proposal for importing and exporting mutable globals.

## Rationale

Without the ability to import and export mutable globals, it is inconvenient to
provide mutable thread-local values that can be dynamically linked, such as the
C++ stack pointer (SP).

The following examples use SP as a motivating example, but a similar argument
can be made for other thread-local variables (or the TLS pointer itself) as
well.

### Example: Dynamically Linking SP with Single Agent

Let's assume we have two modules that are dynamically linked, `m1` and
`m2`. They both use the C++ stack pointer. In the MVP, it's not possible to
import or export a mutable global. In a single-agent program, we can work
around this by storing the stack pointer in linear memory:

```
(module $m1
  (memory (export "memory") 1)
  ;; Address 0 is the address of SP
  ;; The stack starts at 0x100
  (data (i32.const 0) "\00\01\00\00)

  (func
    ;; SP = SP + 64
    (i32.store
      (i32.const 0)  ;; SP
      (i32.add
        (i32.load (i32.const 0))  ;; SP
        (i32.const 64)))
    ...
  )
  ...
)

(module $m2
  (import "env" "memory" (memory 1))
  ...
)
```

Then the modules can be instantiated as follows:

```
WebAssembly.instantiate(m1Bytes, {}).then(
    ({instance}) => {
        let imports = {env: {memory: instance.exports.memory}};
        WebAssembly.instantiate(m2Bytes, imports).then(...);
    });
```

This solution does not work when linear memory is shared, since we need
different memory locations for each stack pointer (one per agent).

### Solution 1: Use Per-Module Immutable Global

One solution is to use a per-module immutable global to store the location of
the SP in linear memory:

```
(module $m1
  (import "env" "spAddr" (global $spAddr i32))
  (memory (export "memory") 1)

  (data (i32.const 0) "\00\01\00\00")  ;; SP for agent 0
  (data (i32.const 4) "\00\02\00\00")  ;; SP for agent 1

  (func
    ;; SP = SP + 64
    (i32.store
      (get_global $spAddr)
      (i32.add
        (i32.load (get_global $spAddr))
        (i32.const 64)))
    ...
  )
  ...
)

(module $m2
  (import "env" "memory" (memory 1))
  (import "env" "spAddr" (global $spAddr i32))
  ...
)
```

Then the modules can be instantiated as follows:

```
let agentIndex = ...;  // 0 or 1, depending on whether this is main thread or a Worker.
let spAddrs = [0x0, 0x4];
let imports = {env: {spAddr: spAddrs[agentIndex]}};
WebAssembly.instantiate(m1Bytes, imports).then(
    ({instance}) => {
        let imports = {env: {
          memory: instance.exports.memory,
          spAddr: spAddrs[agentIndex],
        }};
        WebAssembly.instantiate(m2Bytes, imports).then(...);
    });
```

This principle can be extended to other thread-local variables as well by
changing spAddr to point to the beginning of the agent's TLS.

This works, but has a few drawbacks:

* Every SP access requires reading the global first
* The SP is actually in linear memory, so it can easily be trashed by another
  agent

### Solution 2: Use Internal Mutable Global w/ Shadow in Linear Memory

To reduce the cost of accessing SP, we can store the SP in a mutable global. To
make this work across module boundaries, we spill the SP to a linear memory in
the caller and load the SP in the callee.

This could be optimized to only spill SP when necessary (although this is
complicated by indirect function calls), but for simplicity this example will
just show spilling before function calls and loading at function entries:

```
(module $m1
  (import "env" "shadowSpAddr" (global $shadowSpAddr i32))
  (memory (export "memory") 1)
  (global $sp (mut i32) (i32.const 0))

  (data (i32.const 0) "\00\01\00\00")  ;; Shadow SP for agent 0
  (data (i32.const 4) "\00\02\00\00")  ;; Shadow SP for agent 1

  (func
    ;; Load shadow SP
    (set_global $sp (i32.load (get_global $shadowSpAddr)))

    ;; SP = SP + 64
    (set_global $sp (i32.add (get_global $sp) (i32.const 64)))
    ...
    ;; Function call, spill SP
    (i32.store (get_global $shadowSpAddr) (get_global $sp))
  )
  ...
)

(module $m2
  (import "env" "memory" (memory 1))
  (import "env" "spAddr" (global $shadowSpAddr i32))

  (global $sp (mut i32) (i32.const 0))

  (func
    ;; Load shadow SP
    (set_global $sp (i32.load (get_global $shadowSpAddr)))
    ...
  )
  ...
)
```

The modules would be instantiated the same as they would in solution 1 above:

```
let agentIndex = ...;  // 0 or 1, depending on whether this is main thread or a Worker.
let shadowSpAddrs = [0x0, 0x4];
let imports = {env: {shadowSpAddr: shadowSpAddrs[agentIndex]}};
WebAssembly.instantiate(m1Bytes, imports).then(
    ({instance}) => {
        let imports = {env: {
          memory: instance.exports.memory,
          shadowSpAddr: shadowSpAddrs[agentIndex],
        }};
        WebAssembly.instantiate(m2Bytes, imports).then(...);
    });
```

This solution could be extended to other thread-local variables, but would
have additional overhead for every function call. It's likely to only be
valuable for thread-local values that are used often. In all other cases, it
would be best to just use the shadow values directly.

This solution has the following drawbacks:

* Mostly just a (potential) optimization of solution 1
* All function calls that load/store SP must spill SP at call sites and
  function entrypoints
* Additional thread-local values must also be spilled/loaded in the same way to
  have the same benefit
* The SP is still in linear memory, so it can easily be trashed by another
  agent

### Solution 3: Modify Function Signature to Pass SP as Parameter

Rather than spilling the SP to linear memory, the SP value can be passed as 
a parameter. Because we can't tell whether an imported function will use the
SP, we must modify all exported functions.

The SP will ultimately be saved in a mutable global, but will be loaded from
the parameter at function entrypoints. This is just an optimization; we
could pass the SP to all functions, but it is only necessary to do so in the
exported functions:

```
(module $m1
  (memory (export "memory") 1)
  (global $sp (mut i32) (i32.const 0))

  (func $exported (export "exported") (param $sp i32)
    ;; Load SP from param
    (set_global $sp (get_local $sp))

    ;; SP = SP + 64
    (set_global $sp (i32.add (get_global $sp) (i32.const 64)))
    ...
  )
  ...
)

(module $m2
  (import "env" "memory" (memory 1))
  (import "env" "exported" (func $exported (param $sp i32)))

  (global $sp (mut i32) (i32.const 0))

  (func $internal
    ;; SP doesn't need to be loaded because this function is internal

    ;; SP = SP + 4
    (set_global $sp (i32.add (get_global $sp) (i32.const 4)))

    (call $exported (get_global $sp))
  )
)
```

The modules can then be instantiated as follows:

```
WebAssembly.instantiate(m1Bytes, {}).then(
    ({instance}) => {
        let imports = {env: {
          memory: instance.exports.memory,
          exported: instance.exports.exported,
        }};
        WebAssembly.instantiate(m2Bytes, imports).then(...);
    });
```

But now the JavaScript code must keep a global SP that can be passed to
exported functions. In addition, any functions that call back to JavaScript
must have this SP updated:

```
let sp = 0x200;

function importedFunction(newSp) {
  sp = newSp;
  ...
}

m1.exports.exported(sp);
```

The drawback for this solution is that all exported functions must have an
additional parameter for each thread-local value. This solution could be
extended for other thread-local values, but will very quickly become unwieldy.

### Proposed Solution: Import and Export Mutable Globals

In the MVP, mutable globals cannot be imported or exported. If we loosen this
restriction, we can provide a much nicer solution for thread-local values:

```
(module $m1
  (import "env" "sp" (global $sp (mut i32)))
  (memory (export "memory") 1)

  (func
    ;; SP = SP + 64
    (set_global $sp (i32.add (get_global $sp) (i32.const 64)))
    ...
  )
  ...
)

(module $m2
  (import "env" "memory" (memory 1))
  (import "env" "sp" (global $sp (mut i32)))
  ...

  (func
    ;; SP = SP + 4
    (set_global $sp (i32.add (get_global $sp (i32.const 4))))
  )
)
```

With the modules instantiated as follows:

```
let agentSp = new WebAssembly.Global({type: 'i32', value: 0x100, mutable: true});

let imports = {env: {sp: agentSp}};
WebAssembly.instantiate(m1Bytes, {}).then(
    ({instance}) => {
        let imports = {env: {
          memory: instance.exports.memory,
          sp: agentSp,
        }};
        WebAssembly.instantiate(m2Bytes, imports).then(...);
    });
```

The JavaScript host can now provide a different SP per agent, and share it
between all dynamically linked modules without requiring additional storage for
SP or modifying function signatures.

Similarly, if an imported JavaScript function wants to allocate memory on the
stack, it can modify the global as well:

```

let agentSp = ...;  // As above.

function importedFunction() {
  let addr = agentSp.value;
  // Allocate an 8 byte value on the stack.
  agentSp.value += 8;

  // Fill out data at addr...
  ...

  // Call back into WebAssembly, passing stack-allocated data.
  m1.exports.anotherFunction(addr);
  ...
}
```

## Import/Export Mutable Globals

Imported and exported globals can now be mutable. In the Web binding, exported
globals are now of type `WebAssembly.Global`, rather than converted to a
JavaScript Number.

These globals are local to the [agent][], and cannot be shared between agents.
Globals can therefore be used as
[thread-local storage](https://en.wikipedia.org/wiki/Thread-local_storage).

## `WebAssembly.Global` Objects

A `WebAssembly.Global` object contains a single `global` value which can be
simultaneously referenced by multiple `Instance` objects. Each `Global` object
has two internal slots:

* \[\[Global\]\]: a [`global instance`][]
* \[\[GlobalType\]\]: a [`global_type`][]

#### `WebAssembly.Global` Constructor

The `WebAssembly.Global` constructor has the signature:

```
new Global(globalDescriptor)
```

If the NewTarget is `undefined`, a [`TypeError`][] exception is thrown (i.e.,
this constructor cannot be called as a function without `new`).

If `Type(globalDescriptor)` is not Object, a [`TypeError`][] is thrown.

Let `typeName` be [`ToString`][]([`Get`][](`globalDescriptor`, `"type"`)).

If `typeName` is not one of `"i32"`, `"f32"`, or `"f64"`, throw a [`TypeError`][].

Let `type` be a [`value type`][]:

* If `typeName` is `"i32"`, let `type` be `i32`.
* If `typeName` is `"f32"`, let `type` be `f32`.
* If `typeName` is `"f64"`, let `type` be `f64`.

Let `mutable` be [`ToBoolean`][]([`Get`][](`globalDescriptor`, `"mutable"`)).

Let `mut` be `var` if `mutable` is true, or `const` if `mutable` is false.

Let `value` be [`ToWebAssemblyValue`][]([`Get`][](`globalDescriptor`,
`"value"`)) coerced to `type`.

Return the result of `CreateGlobalObject`(`value`, `mut`, `type`).

#### CreateGlobalObject

Given an initial value `v`, mutability `m`, and type `t` to create a `WebAssembly.Global`:

Let `g` be a new [`global instance`][] with `value` `v` and `mut` `m`.
Let `gt` be a new [`global_type`][] with `mut` `m` and type `t`.

Return a new `WebAssembly.Global` with \[\[Global\]\] set to `g` and \[\[GlobalType\]\] `gt`.

#### `WebAssembly.Global.prototype [ @@toStringTag ]` Property

The initial value of the [`@@toStringTag`][] property is the String value `"WebAssembly.Global"`.

This property has the attributes { [[Writable]]: `false`, [[Enumerable]]: `false`, [[Configurable]]: `true` }.

#### `WebAssembly.Global.prototype [ @@toPrimitive ]` Property

1. If \[\[GlobalType\]\].`valtype` is `i64`, throw a [`TypeError`][].
1. Return [`ToJSValue`][](\[\[Global\]\].`value`).

#### `WebAssembly.Global.prototype.value` Property

This is an accessor property. The [[Set]] accessor function, when called with value `V`,
performs the following steps:

1. If \[\[Global\]\].`mut` is `const`, throw a [`TypeError`][].
1. Let `type` be \[\[GlobalType\]\].`valtype`.
1. If `type` is `i64`, throw a [`TypeError`][].
1. Let `value` be [`ToWebAssemblyValue`][](`V`) coerced to `type`.
1. Set \[\[Global\]\].`value` to `value`.

The [[Get]] accessor function performs the following steps:

1. If \[\[GlobalType\]\].`valtype` is `i64`, throw a [`TypeError`][].
1. Return [`ToJSValue`][](\[\[Global\]\].`value`).

### `WebAssembly.Instance` Constructor

For each [`import`][] `i` in `module.imports`:

1. ...
1. ...
1. ...
1. ...
1. If `i` is a global import:
   1. If `Type(v)` is a Number:
      1. If the `global_type` of `i` is `i64`, throw a `WebAssembly.LinkError`.
      1. Let `globalinst` be a new [`global instance`][] with value [`ToWebAssemblyValue`][](`v`) and mut `i.mut`.
      1. Append `globalinst` to `imports`.
   1. If `Type(v)` is `WebAssembly.Global`, append `v.[[Global]]` to `imports`.
   1. Otherwise: throw a `WebAssembly.LinkError`.

...

Let `exports` be a list of (string, JS value) pairs that is mapped from each
[`external`][] value `e` in `instance.exports` as follows:

1. ...
1. If `e` is a [`global instance`][] `g` with [`global_type`][] `gt`:
   1. Return a new `WebAssembly.Global` with \[\[Global\]\] set to `g` and \[\[GlobalType\]\] set to `gt`.

[agent]: Overview.md#agents-and-agent-clusters
[`external`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/instance.ml#L24
[`Get`]: https://tc39.github.io/ecma262/#sec-get-o-p
[global]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/instance.ml#L15
[`global_type`]: https://webassembly.github.io/spec/syntax/types.html#global-types
[`global instance`]: http://webassembly.github.io/spec/execution/runtime.html#global-instances
[`import`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/ast.ml#L168
[`ToBoolean`]: https://tc39.github.io/ecma262/#sec-toboolean
[`ToJSValue`]: https://github.com/WebAssembly/design/blob/master/JS.md#tojsvalue
[`ToString`]: https://tc39.github.io/ecma262/#sec-tostring
[`@@toStringTag`]: https://tc39.github.io/ecma262/#sec-well-known-symbols
[`ToWebAssemblyValue`]: https://github.com/WebAssembly/design/blob/master/JS.md#towebassemblyvalue
[`TypeError`]: https://tc39.github.io/ecma262/#sec-native-error-types-used-in-this-standard-typeerror
[`value type`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/types.ml#L3
