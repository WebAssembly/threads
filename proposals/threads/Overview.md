# Threading proposal for WebAssembly

This page describes a proposal for the post-MVP
[threads feature :atom_symbol:][future threads].

This proposal adds a new shared linear memory type and some new operations for
atomic memory access. The responsibility of creating and joining threads is
deferred to the embedder.

## Agents and Agent Clusters

An *agent* is the execution context for a WebAssembly module. For the web 
embedding, it is an [ECMAScript agent][]. It is further extended to include a
[WebAssembly stack][] and [evaluation context][].

An agent is sometimes called a *thread*, as it is meant to match the behavior
of the general computing concept of [threads][].

All agents are members of an *agent cluster*. For the web embedding, this is an
[ECMAScript agent cluster][].

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

When linear memory is shared, it is possible for another module (or in the web 
embedding, for JavaScript code) to read from the linear memory as it is being
initialized.

The data segments are initialized as follows, whether they apply to shared or
non-shared linear memory:

* Data segments are initialized in their definition order
* From low to high bytes
* At byte granularity (which can be coalesced)
* As non-atomics
* An entire module's data section initialization then synchronizes with other
  operations (effectively, followed by a barrier)
  
The intention is to allow the implementor to "memcpy" the initializer data into
place.

### Initializing Memory Only Once

The data segments are always copied into linear memory, even if the same module
is instantiated again in another agent. One way to ensure that linear memory is
only initialized once is to place all data segments in a separate module that
is only instantiated once, then share the linear memory with other modules.
For example:

```
;; Data module
(module $data_module
  (memory (export "memory") 1)
  (data (i32.const 0) "..."))
  
;; Main module
(module $main_module
  (import "env" "memory" (memory 1))
  ...)

WebAssembly.instantiate(dataModuleBytes, {}).then(
    ({instance} => {
        let imports = {env: {memory: instance.exports.memory}};
        WebAssembly.instantiate(mainModuleBytes, imports).then(...);
    });
```

## Import/Export Mutable Globals

See [Globals.md](Globals.md).

## New Sign-extending Operators

All atomic RMW operators are zero-extending. To support sign-extending, five
new sign-extension operators are added:

  * `i32.extend8_s`: extend a signed 8-bit integer to a 32-bit integer
  * `i32.extend16_s`: extend a signed 16-bit integer to a 32-bit integer
  * `i64.extend8_s`: extend a signed 8-bit integer to a 64-bit integer
  * `i64.extend16_s`: extend a signed 16-bit integer to a 64-bit integer
  * `i64.extend32_s`: extend a signed 32-bit integer to a 64-bit integer
  
Note that `i64.extend32_s` was not originally included when this proposal was
discussed in the May 2017 CG meeting. The reason given was that 
the behavior matches `i64.extend_s/i32`. It was later discovered that this is
not correct, as `i64.extend_s/i32` sign-extends an `i32` value to `i64`,
whereas `i64.extend32_s` sign-extends an `i64` value to `i64`. The behavior
of `i64.extend32_s` can be emulated with `i32.wrap/i64` followed by
`i64.extend_s/i32`, but the same can be said of the sign-extending load
operations. Therefore, `i64.extend32_s` has been added for consistency.

## Atomic Memory Accesses

Atomic memory accesses are separated into three categories, load/store,
read-modify-write, and compare-exchange. All atomic memory accesses require a
shared linear memory. Attempting to use atomic access operators on non-shared
linear memory is a validation error.

Currently all atomic memory access instructions are [sequentially consistent][].
Instructions with other memory orderings may be provided in the future.

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

For the web embedding, the agent can also be suspended or woken via the
[`Atomics.wait`][] and [`Atomics.wake`][] functions respectively. An agent will
not be suspended for other reasons, unless all agents in that cluster are
also suspended.

An agent suspended via `Atomics.wait` can be woken by the WebAssembly `wake`
operator. Similarly, an agent suspended by `i32.wait` or `i64.wait` can be
woken by [`Atomics.wake`][].

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
| `0` | "ok", woken by another agent in the cluster |
| `1` | "not-equal", the loaded value did not match the expected value |
| `2` | "timed-out", not woken before timeout expired |

The wait operation begins by performing an atomic load from the given address.
If the loaded value is not equal to the expected value, the operator returns 1
("not-equal"). If the values are equal, the agent is suspended. If the agent
is woken, the wait operator returns 0 ("ok"). If the timeout expires before
another agent wakes this one, this operator returns 2 ("timed-out"). Note that
when the agent is suspended, it will not be [spuriously woken](https://en.wikipedia.org/wiki/Spurious_wakeup).
The agent is only woken by `wake` (or [`Atomics.wake`][] in the web embedding).

  * `i32.wait`: load i32 value, compare to expected (as `i32`), and wait for wake at same address
  * `i64.wait`: load i64 value, compare to expected (as `i64`), and wait for wake at same address
  
For the web embedding, `i32.wait` is equivalent in behavior to executing the following:

1. Let `memory` be a `WebAssembly.Memory` object for this module.
1. Let `buffer` be `memory`([`Get`][](`memory`, `"buffer"`)).
1. Let `int32array` be [`Int32Array`][](`buffer`).
1. Let `result` be [`Atomics.wait`][](`int32array`, `address`, `expected`, `timeout`),
   where `address`, `expected`, and `timeout` are the operands to the `wait` operator
   as described above.
1. Return an `i32` value as described in the above table:
   ("ok" -> `0`, "not-equal" -> `1`, "timed-out" -> `2`).
   
`i64.wait` has no equivalent in ECMAScript as it is currently specified, as there is
no `Int64Array` type, and an ECMAScript `Number` cannot represent all values of a
64-bit integer. That said, the behavior can be approximated as follows:

1. Let `memory` be a `WebAssembly.Memory` object for this module.
1. Let `buffer` be `memory`([`Get`][](`memory`, `"buffer"`)).
1. Let `int64array` be `Int64Array`[](`buffer`), where `Int64Array` is a
   typed-array constructor that allows 64-bit integer views with an element size 
   of `8`.
1. Let `result` be [`Atomics.wait`][](`int64array`, `address`, `expected`, `timeout`),
   where `address`, `expected`, and `timeout` are the operands to the `wait` operator
   as described above. The [`Atomics.wait`][] operation is modified:
   1. `ValidateSharedIntegerTypedArray` will fail if the typed-array type is not an
      `Int64Array`.
   1. `value` is not converted to an `Int32`, but kept in a 64-bit integer
      representation.
   1. `indexedPosition` is (`i` x 8) + `offset`
1. Return an `i32` value as described in the above table:
   ("ok" -> `0`, "not-equal" -> `1`, "timed-out" -> `2`).

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
  
For the web embedding, `wake` is equivalent in behavior to executing the following:

1. Let `memory` be a `WebAssembly.Memory` object for this module.
1. Let `buffer` be `memory`([`Get`][](`memory`, `"buffer"`)).
1. Let `int32array` be [`Int32Array`][](`buffer`).
1. Let `fcount` be `count` if `count` is >= 0, otherwise `∞`.
1. Let `result` be [`Atomics.wake`][](`int32array`, `address`, `fcount`).
1. Return `result` converted to an `i32`.

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

If `shared` is `true`, and [`HasProperty`][](`"maximum"`) is `false`, then a
[`TypeError`][] is thrown.

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

Let `status` be the result of calling [`SetIntegrityLevel`][](`buffer`, `"frozen"`).

If `status` is `false`, a [`TypeError`][] is thrown.

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

Perform [`Memory.grow`][] with delta `d`. On failure, a [`RangeError`][] is
thrown.

Return `ret` as a Number value.

### `WebAssembly.Memory.prototype.buffer`

This is an accessor property whose [[Set]] is Undefined and whose [[Get]]
accessor function performs the following steps:

1. If `this` is not a `WebAssembly.Memory`, throw a [`TypeError`][] 
   exception.
1. Otherwise:
  1. If `m` is not shared, then return `M.[[BufferObject]]`.
  1. Otherwise:
    1. Let `newByteLength` be the byte length of `M.[[Memory]]`.
    1. Let `oldByteLength` be
       `M.[[BufferObject]].`[\[\[ArrayBufferByteLength\]\]][].
    1. If `newByteLength` is equal to `oldByteLength`, then return
       `M.[[BufferObject]]`.
    1. Otherwise:
      1. Let `buffer` be a new [`SharedArrayBuffer`][] whose
         [\[\[ArrayBufferData\]\]][] aliases `M.[[Memory]]` and whose
         [\[\[ArrayBufferByteLength\]\]][] is set to `newByteLength`.
      1. Let `status` be [`SetIntegrityLevel`][](`buffer`, `"frozen"`).
      1. If `status` is `false`, throw a [`TypeError`][] exception.
      1. Set `M.[[BufferObject]]` to `buffer`.
      1. Return `buffer`.

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
           0x03 n:u32 m:u32    => {min n, max m, shared}
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
          inn.atomic.load8_u memarg | inn.atomic.load16_u memarg | i64.atomic.load32_u memarg |
          inn.atomic.store8 memarg | inn.atomic.store16 memarg | i64.atomic.store32 memarg |

          inn.atomic.rmw.atomicop memarg |
          inn.atomic.rmw8_u.atomicop memarg |
          inn.atomic.rmw16_u.atomicop memarg |
          i64.atomic.rmw32_u.atomicop memarg |
```

The [instruction binary format][] is modified as follows:

```
memarg8  ::= 0x00 o: offset     =>  {align 0, offset: o}
memarg16 ::= 0x01 o: offset     =>  {align 1, offset: o}
memarg32 ::= 0x02 o: offset     =>  {align 2, offset: o}
memarg64 ::= 0x03 o: offset     =>  {align 3, offset: o}

instr ::= ...
        | 0xC0                  =>  i32.extend8_s
        | 0xC1                  =>  i32.extend16_s
        | 0xC2                  =>  i64.extend8_s
        | 0xC3                  =>  i64.extend16_s
        | 0xC4                  =>  i64.extend32_s

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

[ECMAScript agent]: https://tc39.github.io/ecma262/#sec-agents
[ECMAScript agent cluster]: https://tc39.github.io/ecma262/#sec-agent-clusters
[WebAssembly stack]: https://webassembly.github.io/spec/exec/runtime.html#stack
[evaluation context]: https://webassembly.github.io/spec/exec/runtime.html#evaluation-contexts
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
[`IsSharedArrayBuffer`]: https://tc39.github.io/ecma262/#sec-issharedarraybuffer
[`SetIntegrityLevel`]: https://tc39.github.io/ecma262/#sec-setintegritylevel
[`Atomics.wait`]: https://tc39.github.io/ecma262/#sec-atomics.wait
[`Atomics.wake`]: https://tc39.github.io/ecma262/#sec-atomics.wake
[`Int32Array`]: https://tc39.github.io/ecma262/#sec-typedarray-objects
