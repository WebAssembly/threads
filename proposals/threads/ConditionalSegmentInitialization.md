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
;; The module.
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

## Solution 3: New instructions to initialize data and element segments

Similar to solution 2, we repurpose the memory index as a flags field. Unlike
solution 2, the flags field specifies whether this segment is _inactive_. An
inactive segment will not be automatically copied into the memory or table on
instantiation, and must instead be applied manually using two new instructions:
`init_memory` and `init_table`.

When the least-significant bit of the flags field is `1`, the segment is
inactive. The rest of the bits of the flags field must be zero.

An inactive segment has no initializer expression, since it will be specified
as an operand to `init_memory` or `init_table`.

The data section is encoded as follows:

```
datasec ::= seg*:section\_11(vec(data))   => seg
data    ::= 0x00 e:expr b*:vec(byte)      => {data 0, offset e, init b*, active true}
data    ::= 0x01 b*:vec(byte)             => {data 0, offset empty, init b*, active false}
```

The element section is encoded similarly.

### `init_memory` instruction

The `init_memory` instruction copies data from a given segment into a target
memory. The source segment and target memory are given as immediates. The
instruction also has three i32 operands: an offset into the source segment, an
offset into the target memory, and a length to copy.

When `init_memory` is executed, its behavior matches the steps described in
step 11 of
[instantiation](https://webassembly.github.io/spec/exec/modules.html#instantiation),
but it behaves as though the segment were specified with the source offset,
target offset, and length as given by the `init_memory` operands.

A trap occurs if any of the accessed bytes lies outside the source data segment
or the target memory.

Note that it is allowed to use `init_memory` on the same data segment more than
once, or with an active data segment.

### `init_table` instruction

The `init_table` instruction behaves similary to the `init_memory` instruction,
with the difference that it operates on element segments and tables, instead of
data segments and memories. The offset and length operands of `init_table` have
element units instead of bytes as well.

### Example

Consider the example given in solution 2; there are two data sections, the
first is always active and the second is conditionally active if global 0 has a
non-zero value. This could be implemented as follows:

```
(import "a" "global" (global i32))  ;; global 0
(memory 1)
(data (i32.const 0) "hello")    ;; data segment 0, is active so always copied
(data inactive "goodbye")       ;; data segment 1, is inactive

(func $start
  (if (get\_global 0)
    ;; copy data segment 1 into memory
    (init\_memory 1
      (i32.const 0)     ;; source offset
      (i32.const 16)    ;; target offset
      (i32.const 7)))   ;; length
)
```
