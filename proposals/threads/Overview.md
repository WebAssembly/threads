# Threading proposal for WebAssembly

This page describes a proposal for the post-MVP
[threads feature :atom_symbol:][future threads].

This proposal adds a new shared linear memory type and some new operations for
atomic memory access. The responsibility of creating and joining threads is
deferred to the embedder.

## Agents

An *agent* is the execution context for a WebAssembly module. It comprises a
module, a value stack, a control flow stack, a call stack, and an executing
thread.

The agent's executing thread evaluates instructions and modifies the value
stack, call stack, and control flow stack as specified [here][execution spec].

An agent is sometimes called a *thread*, as it is meant to match the behavior
of the general computing concept of [threads][].

## Agent Clusters

An *agent cluster* is a maximal set of agents that can communicate by operating
on shared memory.

Every agent belongs to exactly one agent cluster.

The embedder may deactivate or activate an agent without the agent's knowledge
or cooperation, but must not leave some agents in the cluster active while
other agents in the cluster are deactivated indefinitely.

An embedder may terminate an agent without any of the agent's cluster's other
agents' prior knowledge or cooperation.

## Shared Linear Memory

A linear memory can be marked as shared, which allows it to be shared between
all agents in an agent cluster. The shared memory can be imported or defined in
the module. It is a validation error to attempt to import shared linear memory
if the module's memory import doesn't specify that it allows shared memory.
Similarly, it is a validation error to import non-shared memory if the
module's memory import specifies it as being shared.

When memory is shared between agents, modifications to the linear memory by one
agent can be observed by another agent in the agent cluster.

### Resizing

If linear memory is marked as shared, the maximum memory size must be
specified.

`grow_memory` and `current_memory` have [sequentially consistent][] ordering.

`grow_memory` of a shared linear memory is allowed. Like non-shared memory, it
fails if the new size is greater than the memory's maximum size, and it may
also fail if reserving the additional memory fails. All agents in the executing
agent's cluster will have access to the additional linear memory.

### Instantiation

When a module has an imported linear memory, its data segments are copied into
the linear memory when the module is instantiated.

When the imported linear memory is shared, the writes are non-atomic and
are not ordered.

## Import/Export Mutable Globals

Imported and exported globals can now be mutable. In the Web binding, exported
globals are now of type `WebAssembly.Global`, rather than converted to a
JavaScript Number.

These globals are local to the agent, and cannot be shared between agents.
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

## New Sign-extending Operators

All atomic RMW operators are zero-extending. To support sign-extending, four
new sign-extension operators are added:

  * `i32.extend_s/i8`: extend a signed 8-bit integer to a 32-bit integer
  * `i32.extend_s/i16`: extend a signed 16-bit integer to a 32-bit integer
  * `i64.extend_s/i8`: extend a signed 8-bit integer to a 64-bit integer
  * `i64.extend_s/i16`: extend a signed 16-bit integer to a 64-bit integer

## Atomic Memory Accesses

Atomic memory accesses are separated into three categories, load/store,
read-modify-write, and compare-exchange. All atomic memory accesses require a
shared linear memory. Attempting to use atomic access operators on non-shared
linear memory is a validation error.

Currently all atomic memory accesses are [sequentially consistent][]. This
restriction may be relaxed in the future.

### Load/Store

Atomic load/store memory accesses behave like their non-atomic counterparts,
with the exception that the ordering of accesses is sequentially consistent.

  * `i32.atomic.load8_u`: atomically load 1 byte and zero-extend i8 to i32
  * `i32.atomic.load16_u`: atomically load 2 bytes and zero-extend i16 to i32
  * `i32.atomic.load`: atomically load 4 bytes as i32
  * `i64.atomic.load8_u`: atomically load 1 byte and zero-extend i8 to i64
  * `i64.atomic.load16_u`: atomically load 2 bytes and zero-extend i16 to i64
  * `i64.atomic.load32_u`: atomically load 4 bytes and zero-extend i32 to i64
  * `i64.atomic.load`: atomically load 8 bytes as i64
  * `i32.atomic.store8`: wrap i32 to i8 and atomically store 1 byte
  * `i32.atomic.store16`: wrap i32 to i16 and atomically store 2 bytes
  * `i32.atomic.store`: (no conversion) atomically store 4 bytes
  * `i64.atomic.store8`: wrap i64 to i8 and atomically store 1 byte
  * `i64.atomic.store16`: wrap i64 to i16 and atomically store 2 bytes
  * `i64.atomic.store32`: wrap i64 to i32 and atomically store 4 bytes
  * `i64.atomic.store`: (no conversion) atomically store 8 bytes

### Read-Modify-Write

Atomic read-modify-write (RMW) operators atomically read a value from an
address, modify the value, and store the resulting value to the same address.
All RMW operators return the value read from memory before the modify operation
was performed.

The RMW operators have two operands, an address and a value used in the modify
operation.

| Name | Read (as `read`) | Modify | Write | Return `read` |
| ---- | ---- | ---- | ---- | ---- |
| `i32.atomic.rmw8_u.add` | 1 byte | 8-bit sign-agnostic addition | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_u.add` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.add` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | as i32 |
| `i64.atomic.rmw8_u.add` | 1 byte | 8-bit sign-agnostic addition | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_u.add` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_u.add` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.add` | 8 bytes | 64-bit sign-agnostic addition | 8 bytes | as i64 |
| `i32.atomic.rmw8_u.sub` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_u.sub` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.sub` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | as i32 |
| `i64.atomic.rmw8_u.sub` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_u.sub` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_u.sub` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.sub` | 8 bytes | 64-bit sign-agnostic subtraction | 8 bytes | as i64 |
| `i32.atomic.rmw8_u.and` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_u.and` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.and` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | as i32 |
| `i64.atomic.rmw8_u.and` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_u.and` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_u.and` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.and` | 8 bytes | 64-bit sign-agnostic bitwise and | 8 bytes | as i64 |
| `i32.atomic.rmw8_u.or` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_u.or` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.or` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | as i32 |
| `i64.atomic.rmw8_u.or` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_u.or` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_u.or` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.or` | 8 bytes | 64-bit sign-agnostic bitwise inclusive or | 8 bytes | as i64 |
| `i32.atomic.rmw8_u.xor` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_u.xor` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.xor` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | as i32 |
| `i64.atomic.rmw8_u.xor` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_u.xor` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_u.xor` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.xor` | 8 bytes | 64-bit sign-agnostic bitwise exclusive or | 8 bytes | as i64 |
| `i32.atomic.rmw8_u.xchg` | 1 byte | nop | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_u.xchg` | 2 bytes | nop | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.xchg` | 4 bytes | nop | 4 bytes | as i32 |
| `i64.atomic.rmw8_u.xchg` | 1 byte | nop | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_u.xchg` | 2 bytes | nop | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_u.xchg` | 4 bytes | nop | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.xchg` | 8 bytes | nop | 8 bytes | as i64 |


### Compare Exchange

The atomic compare exchange operators take three operands: an address, an
`expected` value, and a `replacement` value. If the `loaded` value is equal to
the `expected` value, the `replacement` value is stored to the same memory
address. If the values are not equal, no value is stored. In either case, the
`loaded` value is returned.

| Name | Load (as `loaded`) | Compare `expected` with `loaded` | Conditionally Store `replacement` | Return `loaded` |
| ---- | ---- | ---- | ---- | ---- |
| `i32.atomic.rmw8_u.cmpxchg` | 1 byte | `expected` wrapped from i32 to i8, 8-bit compare equal | wrapped from i32 to i8, store 1 byte | zero-extended from i8 to i32 |
| `i32.atomic.rmw16_u.cmpxchg` | 2 bytes | `expected` wrapped from i32 to i16, 16-bit compare equal | wrapped from i32 to i16, store 2 bytes | zero-extended from i8 to i32 |
| `i32.atomic.rmw.cmpxchg` | 4 bytes | 32-bit compare equal | store 4 bytes | as i32 |
| `i64.atomic.rmw8_u.cmpxchg` | 1 byte | `expected` wrapped from i64 to i8, 8-bit compare equal | wrapped from i64 to i8, store 1 byte | zero-extended from i8 to i64 |
| `i64.atomic.rmw16_u.cmpxchg` | 2 bytes | `expected` wrapped from i64 to i16, 16-bit compare equal | wrapped from i64 to i16, store 2 bytes | zero-extended from i16 to i64 |
| `i64.atomic.rmw32_u.cmpxchg` | 4 bytes | `expected` wrapped from i64 to i32, 32-bit compare equal | wrapped from i64 to i32, store 4 bytes | zero-extended from i32 to i64 |
| `i64.atomic.rmw.cmpxchg` | 8 bytes | 64-bit compare equal | 8 bytes | as i64 |

### Alignment

Unlike normal memory accesses, misaligned atomic accesses trap. For non-atomic
accesses on shared linear memory, misaligned accesses do not trap.

It is a validation error if the alignment field of the memory access immediate
has any other value than the natural alignment for that access size.

## Wait and Wake operators

The wake and wait operators are optimizations over busy-waiting for a value to
change. It is a validation error to use these operators on non-shared linear
memory. The operators have sequentially consistent ordering.

Both wake and wait operators trap if the effective address of either operator
is misaligned or out-of-bounds. The wait operators requires an alignment of
their memory access size. The wait operator requires an alignment of 32 bits.

The embedder is also permitted to suspend or wake an agent. A suspended agent
can be woken by the embedder or the wake operator, regardless of how the agent
was suspended (e.g. via the embedder or a wait operator).

### Wait

The wait operator take three operands: an address operand, an expected value,
and a relative timeout in milliseconds as an `f64`. The return value is `0`,
`1`, or `2`, returned as an `i32`.

| `timeout` value | Behavior |
| ---- | ---- |
| `timeout` <= 0 | Expires immediately |
| 0 < `timeout` < Positive infinity | Expires after `timeout` milliseconds |
| Positive infinity | Never expires |
| NaN | Never expires |

| Return value | Description |
| ---- | ---- |
| `0` | "ok", woken by another agent in the cluster or the embedder |
| `1` | "not-equal", the loaded value did not match the expected value |
| `2` | "timed-out", not woken before timeout expired |

The wait operation begins by performing an atomic load from the given address.
If the loaded value is not equal to the expected value, the operator returns 1
("not-equal"). If the values are equal, the agent is suspended. If the agent
is woken, the wait operator returns 0 ("ok"). If the timeout expires before
another agent wakes this one, this operator returns 2 ("timed-out").

  * `i32.wait`: load i32 value, compare to expected (as `i32`), and wait for wake at same address
  * `i64.wait`: load i64 value, compare to expected (as `i64`), and wait for wake at same address

### Wake

The wake operator takes two operands: an address operand and a wake count as an
`i32`. The operation will wake as many waiters as are waiting on the same
effective address, up to the maximum as specified by `wake count`. The operator
returns the number of waiters that were woken as an `i32`.

`wake count` value | Behavior |
| ---- | ---- |
| `wake count` < 0 | Wake all waiters |
| `wake count` == 0 | Wake no waiters |
| `wake count` > 0 | Wake min(`wake count`, `num waiters`) waiters |

  * `wake`: wake up `wake count` threads waiting on the given address via `i32.wait` or `i64.wait`

## [JavaScript API][] changes

### `WebAssembly.Memory` Constructor

See the current specification [here][WebAssembly.Memory].

The WebAssembly.Memory constructor has the same signature:

```
new Memory(memoryDescriptor)
```

However, the `memoryDescriptor` now will check for a `shared` property:

Let `shared` be [`ToBoolean`][]([`Get`][](`memoryDescriptor`, `"shared"`)).
Otherwise, let `shared` be `false`.

Let `memory` be the result of calling [`Memory.create`][] given arguments
`initial`, `maximum`, and `shared`. Note that `initial` and `maximum` are
specified in units of WebAssembly pages (64KiB).

Return the result of [`CreateMemoryObject`](#creatememoryobject)(`memory`).

### `CreateMemoryObject`

Given a [`Memory.memory`][] `m`, to create a `WebAssembly.Memory`:

If `m` is shared, let `buffer` be a new [`SharedArrayBuffer`][]. If `m` is not
shared, let `buffer` be a new [`ArrayBuffer`][]. In either case, `buffer` will
have an internal slot [\[\[ArrayBufferData\]\]][] which aliases `m` and an
internal slot [\[\[ArrayBufferByteLength\]\]][] which is set to the byte length
of `m`.

If `m` is shared, any attempts to [`detach`][] `buffer` shall throw a
[`TypeError`][]. Note that `buffer` is never detached when `m` is shared,
even when `m.grow` is performed.

If `m` is not shared, any attempts to detach `buffer` _other_ than the
detachment performed by `m.grow` shall throw a [`TypeError`][].

Return a new `WebAssembly.Memory` instance with `[[Memory]]` set to `m` and
`[[BufferObject]]` set to `buffer`.

### `WebAssembly.Memory.prototype.grow`

Let `M` be the `this` value. If `M` is not a `WebAssembly.Memory`, a
[`TypeError`][] is thrown.

If [`IsSharedArrayBuffer`][](`M.[[BufferObject]]`) is false, then this
function behaves as described [here][WebAssembly.Memory.prototype.grow].
Otherwise:

Let `d` be [`ToNonWrappingUint32`][](`delta`).

Let `ret` be the current size of memory in pages (before resizing).

Perform [`Memory.grow`][] with delta `d`. On failure, a [`RangeError`][] is thrown.

Assign to `M.[[BufferObject]]` a new [`SharedArrayBuffer`][] whose
[\[\[ArrayBufferData\]\]][] aliases `M.[[Memory]]` and whose
[\[\[ArrayBufferByteLength\]\]][] is set to the new byte length of
`M.[[Memory]]`.

Return `ret` as a Number value.

### `WebAssembly.Global` Objects

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

## [Spec Changes][spec]

The [limits type][] now has an additional field specifying whether
the linear memory or table is shared:

```
limits ::= {min u32, max u32?, share}
share  ::= notshared | shared
```

Its [encoding][limits encoding] is as follows:

```
limits ::= 0x00 n:u32          => {min n, max e, notshared}
           0x01 n:u32 m:u32    => {min n, max m, notshared}
           0x11 n:u32 m:u32    => {min n, max m, shared}
```

Note that shared linear memory without an explicit maximum size is not
permitted. This allows the embedder to reserve enough virtual memory for the
maximum size so the base address of the linear memory does not have to change.
Modifying the base address would require suspending all threads, which is
burdensome.

The [instruction syntax][] is modified as follows:

```
atomicop ::= add | sub | and | or | xor | xchg | cmpxchg

instr ::= ... |
          inn.wait memarg |
          wake memarg |

          inn.extend_s/i8 |
          inn.extend_s/i16 |

          inn.atomic.load memarg | inn.atomic.store memarg |
          inn.atomic.load8_sx memarg | inn.atomic.load16_sx memarg | i64.atomic.load32_sx memarg |
          inn.atomic.store8 memarg | inn.atomic.store16 memarg | i64.atomic.store32 memarg |

          inn.atomic.rmw.atomicop memarg |
          inn.atomic.rmw8_sx.atomicop memarg |
          inn.atomic.rmw16_sx.atomicop memarg |
          i64.atomic.rmw32_sx.atomicop memarg |
```

The [instruction binary format][] is modified as follows:

```
memarg8  ::= 0x00 o: offset     =>  {align 0, offset: o}
memarg16 ::= 0x01 o: offset     =>  {align 1, offset: o}
memarg32 ::= 0x02 o: offset     =>  {align 2, offset: o}
memarg64 ::= 0x03 o: offset     =>  {align 3, offset: o}

instr ::= ...
        | 0xC0                  =>  i32.extend_s/i8
        | 0xC1                  =>  i32.extend_s/i16
        | 0xC2                  =>  i64.extend_s/i8
        | 0xC3                  =>  i64.extend_s/i16

        | 0xFE 0x00 m:memarg32  =>  wake m
        | 0xFE 0x01 m:memarg32  =>  i32.wait m
        | 0xFE 0x02 m:memarg64  =>  i64.wait m

        | 0xFE 0x10 m:memarg32  =>  i32.atomic.load m
        | 0xFE 0x11 m:memarg64  =>  i64.atomic.load m
        | 0xFE 0x12 m:memarg8   =>  i32.atomic.load8_u m
        | 0xFE 0x13 m:memarg16  =>  i32.atomic.load16_u m
        | 0xFE 0x14 m:memarg8   =>  i64.atomic.load8_u m
        | 0xFE 0x15 m:memarg16  =>  i64.atomic.load16_u m
        | 0xFE 0x16 m:memarg32  =>  i64.atomic.load32_u m
        | 0xFE 0x17 m:memarg32  =>  i32.atomic.store m
        | 0xFE 0x18 m:memarg64  =>  i64.atomic.store m
        | 0xFE 0x19 m:memarg8   =>  i32.atomic.store8 m
        | 0xFE 0x1A m:memarg16  =>  i32.atomic.store16 m
        | 0xFE 0x1B m:memarg8   =>  i64.atomic.store8 m
        | 0xFE 0x1C m:memarg16  =>  i64.atomic.store16 m
        | 0xFE 0x1D m:memarg32  =>  i64.atomic.store32 m

        | 0xFE 0x1E m:memarg32  =>  i32.atomic.rmw.add m
        | 0xFE 0x1F m:memarg64  =>  i64.atomic.rmw.add m
        | 0xFE 0x20 m:memarg8   =>  i32.atomic.rmw8_u.add m
        | 0xFE 0x21 m:memarg16  =>  i32.atomic.rmw16_u.add m
        | 0xFE 0x22 m:memarg8   =>  i64.atomic.rmw8_u.add m
        | 0xFE 0x23 m:memarg16  =>  i64.atomic.rmw16_u.add m
        | 0xFE 0x24 m:memarg32  =>  i64.atomic.rmw32_u.add m

        | 0xFE 0x25 m:memarg32  =>  i32.atomic.rmw.sub m
        | 0xFE 0x26 m:memarg64  =>  i64.atomic.rmw.sub m
        | 0xFE 0x27 m:memarg8   =>  i32.atomic.rmw8_u.sub m
        | 0xFE 0x28 m:memarg16  =>  i32.atomic.rmw16_u.sub m
        | 0xFE 0x29 m:memarg8   =>  i64.atomic.rmw8_u.sub m
        | 0xFE 0x2A m:memarg16  =>  i64.atomic.rmw16_u.sub m
        | 0xFE 0x2B m:memarg32  =>  i64.atomic.rmw32_u.sub m

        | 0xFE 0x2C m:memarg32  =>  i32.atomic.rmw.and m
        | 0xFE 0x2D m:memarg64  =>  i64.atomic.rmw.and m
        | 0xFE 0x2E m:memarg8   =>  i32.atomic.rmw8_u.and m
        | 0xFE 0x2F m:memarg16  =>  i32.atomic.rmw16_u.and m
        | 0xFE 0x30 m:memarg8   =>  i64.atomic.rmw8_u.and m
        | 0xFE 0x31 m:memarg16  =>  i64.atomic.rmw16_u.and m
        | 0xFE 0x32 m:memarg32  =>  i64.atomic.rmw32_u.and m

        | 0xFE 0x33 m:memarg32  =>  i32.atomic.rmw.or m
        | 0xFE 0x34 m:memarg64  =>  i64.atomic.rmw.or m
        | 0xFE 0x35 m:memarg8   =>  i32.atomic.rmw8_u.or m
        | 0xFE 0x36 m:memarg16  =>  i32.atomic.rmw16_u.or m
        | 0xFE 0x37 m:memarg8   =>  i64.atomic.rmw8_u.or m
        | 0xFE 0x38 m:memarg16  =>  i64.atomic.rmw16_u.or m
        | 0xFE 0x39 m:memarg32  =>  i64.atomic.rmw32_u.or m

        | 0xFE 0x3A m:memarg32  =>  i32.atomic.rmw.xor m
        | 0xFE 0x3B m:memarg64  =>  i64.atomic.rmw.xor m
        | 0xFE 0x3C m:memarg8   =>  i32.atomic.rmw8_u.xor m
        | 0xFE 0x3D m:memarg16  =>  i32.atomic.rmw16_u.xor m
        | 0xFE 0x3E m:memarg8   =>  i64.atomic.rmw8_u.xor m
        | 0xFE 0x3F m:memarg16  =>  i64.atomic.rmw16_u.xor m
        | 0xFE 0x40 m:memarg32  =>  i64.atomic.rmw32_u.xor m

        | 0xFE 0x41 m:memarg32  =>  i32.atomic.rmw.xchg m
        | 0xFE 0x42 m:memarg64  =>  i64.atomic.rmw.xchg m
        | 0xFE 0x43 m:memarg8   =>  i32.atomic.rmw8_u.xchg m
        | 0xFE 0x44 m:memarg16  =>  i32.atomic.rmw16_u.xchg m
        | 0xFE 0x45 m:memarg8   =>  i64.atomic.rmw8_u.xchg m
        | 0xFE 0x46 m:memarg16  =>  i64.atomic.rmw16_u.xchg m
        | 0xFE 0x47 m:memarg32  =>  i64.atomic.rmw32_u.xchg m

        | 0xFE 0x48 m:memarg32  =>  i32.atomic.rmw.cmpxchg m
        | 0xFE 0x49 m:memarg64  =>  i64.atomic.rmw.cmpxchg m
        | 0xFE 0x4A m:memarg8   =>  i32.atomic.rmw8_u.cmpxchg m
        | 0xFE 0x4B m:memarg16  =>  i32.atomic.rmw16_u.cmpxchg m
        | 0xFE 0x4C m:memarg8   =>  i64.atomic.rmw8_u.cmpxchg m
        | 0xFE 0x4D m:memarg16  =>  i64.atomic.rmw16_u.cmpxchg m
        | 0xFE 0x4E m:memarg32  =>  i64.atomic.rmw32_u.cmpxchg m
```

[agent]: Overview.md#agents
[agent cluster]: Overview.md#agent-clusters
[threads]: https://en.wikipedia.org/wiki/Thread_(computing)
[execution spec]: https://webassembly.github.io/spec/execution/index.html
[sequentially consistent]: https://en.wikipedia.org/wiki/Sequential_consistency
[future threads]: https://github.com/WebAssembly/design/blob/master/FutureFeatures.md#threads
[limits type]: https://webassembly.github.io/spec/syntax/types.html#limits
[limits encoding]: https://webassembly.github.io/spec/binary/types.html#limits
[instruction syntax]: https://webassembly.github.io/spec/syntax/instructions.html
[instruction binary format]: https://webassembly.github.io/spec/binary/instructions.html
[spec]: https://webassembly.github.io/spec
[JavaScript API]: https://github.com/WebAssembly/design/blob/master/JS.md
[WebAssembly.Memory]: https://github.com/WebAssembly/design/blob/master/JS.md#webassemblymemory-constructor
[WebAssembly.Memory.prototype.grow]: https://github.com/WebAssembly/design/blob/master/JS.md#webassemblymemoryprototypegrow
[`HasProperty`]: https://tc39.github.io/ecma262/#sec-hasproperty
[`ToBoolean`]: https://tc39.github.io/ecma262/#sec-toboolean
[`ToString`]: https://tc39.github.io/ecma262/#sec-tostring
[`Get`]: https://tc39.github.io/ecma262/#sec-get-o-p
[`Memory.create`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/memory.ml#L47
[`Memory.memory`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/memory.mli#L1
[`Memory.grow`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/memory.ml#L60
[`ArrayBuffer`]: https://tc39.github.io/ecma262/#sec-arraybuffer-objects
[`SharedArrayBuffer`]: https://tc39.github.io/ecma262/#sec-sharedarraybuffer-objects
[`detach`]: http://tc39.github.io/ecma262/#sec-detacharraybuffer
[`TypeError`]: https://tc39.github.io/ecma262/#sec-native-error-types-used-in-this-standard-typeerror
[`RangeError`]: https://tc39.github.io/ecma262/#sec-native-error-types-used-in-this-standard-rangeerror
[\[\[ArrayBufferData\]\]]: http://tc39.github.io/ecma262/#sec-properties-of-the-arraybuffer-prototype-object
[\[\[ArrayBufferByteLength\]\]]: http://tc39.github.io/ecma262/#sec-properties-of-the-arraybuffer-prototype-object
[`ToNonWrappingUint32`]: https://github.com/WebAssembly/design/blob/master/JS.md#tononwrappinguint32
[`ToWebAssemblyValue`]: https://github.com/WebAssembly/design/blob/master/JS.md#towebassemblyvalue
[`IsSharedArrayBuffer`]: https://tc39.github.io/ecma262/#sec-issharedarraybuffer
[`value type`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/types.ml#L3
[`global instance`]: http://webassembly.github.io/spec/execution/runtime.html#global-instances
[`external`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/instance.ml#L24
[global]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/instance.ml#L15
[`import`]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/ast.ml#L168
