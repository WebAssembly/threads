# Proposal to conditionally initialize segments

This page describes a proposal for providing a mechanism to skip data or
element segment initialization when instantiating a module.

Although the following rationale applies only to data segments, this proposal
suggests that the proposed solutions apply to element segments as well for
consistency.

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
  (data (i32.const 0) "\0")

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
  ({module, instance}) => {
    // Increment our counter.
    instance.exports.addOne();

    // Spawn a new Worker.
    let worker = new Worker('worker.js');

    // Send the module to the new Worker.
    worker.postMessage(module);
  });

// worker.js

function onmessage(event) {
  let module = event.data;

  // Use the module to create another instance.
  WebAssembly.instantiate(module).then(
    (instance) => {
      // Oops, our counter has been clobbered.
    });
}

```

This can be worked around by storing the data segments in a separate module
which is only instantiated once, then exporting this memory to be used by
another module that contains only code. This works, but it cumbersome since it
requires two modules where one should be enough.

## Solution 1: Provide instantiation flag to prevent segment initialization

We provide a third argument in `WebAssembly.instantiate` and the
`WebAssembly.Instance` constructors. This argument has a type with the
following IDL:

```webidl
dictionary WebAssemblyInstantiateOptions {
  boolean initializeMemory = true;
  boolean initializeTable = true;
}
```

If the `initializeMemory` field's value is `false`, then the memory will not be
initialized from the contents of the module's data segments. Similarly, if the
`initializeTable` field's value is `false`, then the table will not be
initialized from the content of the module's element segments.

`WebAssembly.instantiate` is modified as follows:

```
Promise<WebAssemblyInstantiatedSource>
  instantiate(BufferSource bytes [, importObject] [, options])

Promise<WebAssembly.Instance>
  instantiate(moduleObject [, importObject] [, options])
```

The `WebAssembly.Instance` constructor is modified as follows:

```
new Instance(moduleObject [, importObject] [, options])
```

## Solution 2: Provide an additional initializer expression per segment

### Data Segments

The [binary format for the data section](https://webassembly.github.io/spec/binary/modules.html#data-section)
currently has a collection of segments, each of which has a memory index, an
initializer expression for its offset, and its raw data.

Since WebAssembly currently does not allow for multiple memories, the memory
index must be zero. We can repurpose this field as a flags field.

When the least-significant bit of the flags field is `1`, an additional
initializer expression is included in the segment definition. This initializer
expression is called `apply`. The type of the expression must be `i32`. During
instantiation, the `apply` initializer expression is evaluated for each
segment. If the value is non-zero, the segment will be applied.

If multiple memories are added to WebAssembly in the future, one of the other
flag bits can be used to specify that a memory index is also encoded.

The data section is encoded as follows:

```
datasec ::= seg*:section_11(vec(data))          => seg
data    ::= 0x00 e:expr b*:vec(byte)            => {data 0, offset e, apply (i32.const 1), init b*}
data    ::= 0x01 e_o:expr e_a:expr b*:vec(byte) => {data 0, offset e_o, apply e_a, init b*}
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

### Element segments

Similar changes are made to the [element section](https://webassembly.github.io/spec/binary/modules.html#element-section).

The element section is encoded as follows:

```
elemsec ::= seg*:section_9(vec(elem))                => seg
elem    ::= 0x00 e:expr y*:vec(funcindex)            => {table 0, offset e, apply (i32.const 1), init y*}
elem    ::= 0x01 e_o:expr e_a:expr y*:vec(funcindex) => {table 0, offset e_o, apply e_a, init y*}
```

As with data segments, the `apply` initializer expression is evaluated during
instantiation, and will be applied only if the expression evaluates to a
non-zero value.
