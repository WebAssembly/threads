# Import/Export mutable globals proposal

This page describes a proposal for importing and exporting mutable globals.

## Import/Export Mutable Globals

Imported and exported globals can now be mutable. In the Web binding, exported
globals are now of type `WebAssembly.Global`, rather than converted to a
JavaScript Number.

These globals are local to the [agent][], and cannot be shared between agents.
Globals can therefore be used as
[thread-local storage](https://en.wikipedia.org/wiki/Thread-local_storage).

Rationale:

Without the ability to import and export mutable globals, it is inconvenient to
provide mutable thread-local values that can be dynamically linked, such as the
C++ stack pointer (SP). Here are a few ways that are possible:

1. Use a thread-local shared linear memory location as SP. Use an immutable
   global as the address of SP. Every load/store of SP must first read the
   global to determine SP address.
1. Use an internal mutable global as SP. Store a shadow SP in shared linear
   memory. Use an immutable imported global as the address of the shadow SP. At
   module function call boundaries (e.g. imported and exported functions),
   spill SP to the shadow in the caller, and load in the callee. After the call
   returns to the caller, load SP from shadow SP.
1. Use an internal mutable global as SP. Modify all imported and exported
   functions to pass SP as a parameter. The callee stores the passed SP to its
   internal mutable global.

## `WebAssembly.Global` Objects

A `WebAssembly.Global` object contains a single `global` value which can be
simultaneously referenced by multiple `Instance` objects. Each `Global` object
has one internal slot:

* \[\[Global\]\]: a [`global instance`][]

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

Return the result of `CreateGlobalObject`(`value`, `mut`).

#### CreateGlobalObject

Given an initial value `v`, and mutability `m`, to create a `WebAssembly.Global`:

Let `g` be a new [`global instance`][] with `value` `v` and `mut` `m`.

Return a new `WebAssembly.Global` with \[\[Global\]\] set to `g`.

#### `WebAssembly.Global.prototype [ @@toStringTag ]` Property

TODO

#### `WebAssembly.Global.prototype [ @@toPrimitive ]` Property

TODO

#### `WebAssembly.Global.prototype.value` Property

This property has the attributes { [[Writable]]: `true`, [[Enumerable]]:
`true`, [[Configurable]]: `false` }.

TODO

### `WebAssembly.Instance` Constructor

For each [`import`][] `i` in `module.imports`:

1. ...
1. ...
1. ...
1. ...
1. If `i` is a global import:
   1. If the `global_type` of `i` is `i64`, throw a `WebAssembly.LinkError`. TODO: don't throw?
   1. If `Type(v)` is a Number:
      1. Let `globalinst` be a new [`global instance`][] with value [`ToWebAssemblyValue`][](`v`) and mut `i.mut`.
      1. Append `globalinst` to `imports`.
   1. If `Type(v)` is `WebAssembly.Global`, append `v.[[Global]]` to `imports`.
   1. Otherwise: throw a `WebAssembly.LinkError`.

...

Let `exports` be a list of (string, JS value) pairs that is mapped from each
[`external`][] value `e` in `instance.exports` as follows:

1. ...
1. If `e` is a [`global instance`][] `v`:
   1. Let `type` be the `value_type` of `v.value`.
   1. If `type` is `i64`, throw a `WebAssembly.LinkError`. TODO: don't throw?
   1. Return a new `WebAssembly.Global` with \[\[Global\]\] set to `v`.

[agent]: Overview.md#agents-and-agent-clusters
[`external`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/instance.ml#L24
[`Get`]: https://tc39.github.io/ecma262/#sec-get-o-p
[global]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/instance.ml#L15
[`global instance`]: http://webassembly.github.io/spec/execution/runtime.html#global-instances
[`import`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/ast.ml#L168
[`ToBoolean`]: https://tc39.github.io/ecma262/#sec-toboolean
[`ToString`]: https://tc39.github.io/ecma262/#sec-tostring
[`ToWebAssemblyValue`]: https://github.com/WebAssembly/design/blob/master/JS.md#towebassemblyvalue
[`TypeError`]: https://tc39.github.io/ecma262/#sec-native-error-types-used-in-this-standard-typeerror
[`value type`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/types.ml#L3
