# Data segment initialization flag proposal

This page describes a proposal for providing a flag to skip data segment
initialization when instantiating a module.

## Rationale

Under the current threading proposal, to share a module between multiple
agents, the module must be instantiated multiple times: once per agent.
Instantiation initializes linear memory with the contents in the module's data
segments. If the memory is shared between multiple agents, it will be
initialized multiple times, potentially overwriting stores that occurred after
the previous initializations.

For example:

```webassembly
// The module.
(module
  (memory (export "memory") 1)

  ;; Some value used as a counter.
  (data (i32.const 1) "\0")

  ;; Add one to the counter.
  (func (export "addOne")
    (i32.store8
      (i32.const 0)
      (i32.add
        (i32.load8_u (i32.const 0))
        (i32.const 1)))
  )
)
```

```javascript
// main.js
let moduleBytes = ...;

WebAssembly.instantiate(moduleBytes).then(
  ({instance}) => {
    // Increment our counter.
    instance.exports.addOne();

    // Spawn a new Worker.
    new Worker('worker.js');
  });

// worker.js
let moduleBytes = ...;

WebAssembly.instantiate(moduleBytes).then(
  ({instance}) => {
    // Oops, our counter has been clobbered.
  });
```

This can be worked around by storing the data segments in a separate module
which is only instantiated once, then exporting this memory to be used by
another module that contains only code. This works, but it cumbersome since it
requires two modules where one should be enough.

## Solution 1: Provide instantiation flag to prevent data segment initialization

We provide a third argument in `WebAssembly.instantiate` and the
`WebAssembly.Instance` constructors. This argument has a type with the
following IDL:

```webidl
dictionary WebAssemblyInstantiateOptions {
  boolean initializeMemory = true;
}
```

`WebAssembly.instantiate` is modified as follows:

```
Promise<WebAssemblyInstantiatedSource>
  instantiate(BufferSource bytes [, importObject] [, options])
```

The `WebAssembly.Instance` constructor is modified as follows:

```
new Instance(moduleObject [, importObject] [, options])
```

If the `initializeMemory` field's value is `false`, then the memory will not be
initialized from the contents of the module's data segments.

## Solution 2: Provide an additional initializer expression per data segment

The [binary format for the data section](https://webassembly.github.io/spec/binary/modules.html#data-section)
currently has a collection of segments, each of which has a memory index, an
initializer expression for its offset, and its raw data.

Since WebAssembly currently does not allow for multiple memories, the memory
index must be zero. We can repurpose this field as a flags field and use it to
specify an additional initializer expression which is evaluated to determine
whether the segment should be applied. If the value of this new initializer
expression is non-zero, the segment will be applied.

The data section would be encoded as follows:

```
datasec ::= seg*:section_11(vec(data))          => seg
data    ::= 0x00 e:expr b*:vec(byte)            => {data x, offset e, apply (i32.const 1), init b*}
data    ::= 0x01 e_o:expr e_a:expr b*:vec(byte) => {data x, offset e_o, apply e_a, init b*}
```

For example, a data section could be encoded as follows:

```
;; Data Section
02                       ;; two data segments

;; Segment 0
00                       ;; flags = 0, so no additional init_expr
41 00 0b                 ;; i32.const 0, end => initialize at offset 0
05 68 65 6c 6c 6f        ;; 5 bytes, "hello"

;; Segment 1
01                       ;; flags = 1, so additional init_expr
41 10 0b                 ;; i32.const 16, end => initialize at offset 16
23 00 0b                 ;; get_global 0, end => initialize data iff global 0 has non-zero value
07 67 6f 6f 64 62 79 65  ;; 7 bytes, "goodbye"
```

Segment 0 will be initialized unconditionally. Segment 1 will only be
initialized if global 0 has a non-zero value.

This solution can provide the same functionality as solution 1 by marking all
segments as being applied only when a given global is non-zero, and
initializing that global to one. Then, after instantiating the module the first
time, we set the global to zero so no further data segments are applied.
