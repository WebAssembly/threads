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

  * `i32.atomic.load8_s`: atomically load 1 byte and sign-extend i8 to i32
  * `i32.atomic.load8_u`: atomically load 1 byte and zero-extend i8 to i32
  * `i32.atomic.load16_s`: atomically load 2 bytes and sign-extend i16 to i32
  * `i32.atomic.load16_u`: atomically load 2 bytes and zero-extend i16 to i32
  * `i32.atomic.load`: atomically load 4 bytes as i32
  * `i64.atomic.load8_s`: atomically load 1 byte and sign-extend i8 to i64
  * `i64.atomic.load8_u`: atomically load 1 byte and zero-extend i8 to i64
  * `i64.atomic.load16_s`: atomically load 2 bytes and sign-extend i16 to i64
  * `i64.atomic.load16_u`: atomically load 2 bytes and zero-extend i16 to i64
  * `i64.atomic.load32_s`: atomically load 4 bytes and sign-extend i32 to i64
  * `i64.atomic.load32_u`: atomically load 4 bytes and zero-extend i32 to i64
  * `i64.atomic.load`: atomically load 8 bytes as i64
  * `f32.atomic.load`: atomically load 4 bytes as f32
  * `f64.atomic.load`: atomically load 8 bytes as f64
  * `i32.atomic.store8`: wrap i32 to i8 and atomically store 1 byte
  * `i32.atomic.store16`: wrap i32 to i16 and atomically store 2 bytes
  * `i32.atomic.store`: (no conversion) atomically store 4 bytes
  * `i64.atomic.store8`: wrap i64 to i8 and atomically store 1 byte
  * `i64.atomic.store16`: wrap i64 to i16 and atomically store 2 bytes
  * `i64.atomic.store32`: wrap i64 to i32 and atomically store 4 bytes
  * `i64.atomic.store`: (no conversion) atomically store 8 bytes
  * `f32.atomic.store`: (no conversion) atomically store 4 bytes
  * `f64.atomic.store`: (no conversion) atomically store 8 bytes

### Read-Modify-Write

Atomic read-modify-write (RMW) operators atomically read a value from an
address, modify the value, and store the resulting value to the same address.
All RMW operators return the value read from memory before the modify operation
was performed.

The RMW operators have two operands, an address and a value used in the modify
operation.

| Name | Read (as `read`) | Modify | Write | Return `read` |
| ---- | ---- | ---- | ---- | ---- |
| `i32.atomic.rmw8_s.add` | 1 byte | 8-bit sign-agnostic addition | 1 byte | sign-extended i8 to i32 |
| `i32.atomic.rmw8_u.add` | 1 byte | 8-bit sign-agnostic addition | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_s.add` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | sign-extended i16 to i32 |
| `i32.atomic.rmw16_u.add` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.add` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | as i32 |
| `i64.atomic.rmw8_s.add` | 1 byte | 8-bit sign-agnostic addition | 1 byte | sign-extended i8 to i64 |
| `i64.atomic.rmw8_u.add` | 1 byte | 8-bit sign-agnostic addition | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_s.add` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | sign-extended i16 to i64 |
| `i64.atomic.rmw16_u.add` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_s.add` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | sign-extended i32 to i64 |
| `i64.atomic.rmw32_u.add` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.add` | 8 bytes | 64-bit sign-agnostic addition | 8 bytes | as i64 |
| `i32.atomic.rmw8_s.sub` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | sign-extended i8 to i32 |
| `i32.atomic.rmw8_u.sub` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_s.sub` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | sign-extended i16 to i32 |
| `i32.atomic.rmw16_u.sub` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.sub` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | as i32 |
| `i64.atomic.rmw8_s.sub` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | sign-extended i8 to i64 |
| `i64.atomic.rmw8_u.sub` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_s.sub` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | sign-extended i16 to i64 |
| `i64.atomic.rmw16_u.sub` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_s.sub` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | sign-extended i32 to i64 |
| `i64.atomic.rmw32_u.sub` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.sub` | 8 bytes | 64-bit sign-agnostic subtraction | 8 bytes | as i64 |
| `i32.atomic.rmw8_s.and` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | sign-extended i8 to i32 |
| `i32.atomic.rmw8_u.and` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_s.and` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | sign-extended i16 to i32 |
| `i32.atomic.rmw16_u.and` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.and` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | as i32 |
| `i64.atomic.rmw8_s.and` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | sign-extended i8 to i64 |
| `i64.atomic.rmw8_u.and` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_s.and` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | sign-extended i16 to i64 |
| `i64.atomic.rmw16_u.and` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_s.and` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | sign-extended i32 to i64 |
| `i64.atomic.rmw32_u.and` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.and` | 8 bytes | 64-bit sign-agnostic bitwise and | 8 bytes | as i64 |
| `i32.atomic.rmw8_s.or` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | sign-extended i8 to i32 |
| `i32.atomic.rmw8_u.or` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_s.or` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | sign-extended i16 to i32 |
| `i32.atomic.rmw16_u.or` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.or` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | as i32 |
| `i64.atomic.rmw8_s.or` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | sign-extended i8 to i64 |
| `i64.atomic.rmw8_u.or` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_s.or` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | sign-extended i16 to i64 |
| `i64.atomic.rmw16_u.or` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_s.or` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | sign-extended i32 to i64 |
| `i64.atomic.rmw32_u.or` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.or` | 8 bytes | 64-bit sign-agnostic bitwise inclusive or | 8 bytes | as i64 |
| `i32.atomic.rmw8_s.xor` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | sign-extended i8 to i32 |
| `i32.atomic.rmw8_u.xor` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_s.xor` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | sign-extended i16 to i32 |
| `i32.atomic.rmw16_u.xor` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.xor` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | as i32 |
| `i64.atomic.rmw8_s.xor` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | sign-extended i8 to i64 |
| `i64.atomic.rmw8_u.xor` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_s.xor` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | sign-extended i16 to i64 |
| `i64.atomic.rmw16_u.xor` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_s.xor` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | sign-extended i32 to i64 |
| `i64.atomic.rmw32_u.xor` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.xor` | 8 bytes | 64-bit sign-agnostic bitwise exclusive or | 8 bytes | as i64 |
| `i32.atomic.rmw8_s.xchg` | 1 byte | nop | 1 byte | sign-extended i8 to i32 |
| `i32.atomic.rmw8_u.xchg` | 1 byte | nop | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16_s.xchg` | 2 bytes | nop | 2 bytes | sign-extended i16 to i32 |
| `i32.atomic.rmw16_u.xchg` | 2 bytes | nop | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.xchg` | 4 bytes | nop | 4 bytes | as i32 |
| `i64.atomic.rmw8_s.xchg` | 1 byte | nop | 1 byte | sign-extended i8 to i64 |
| `i64.atomic.rmw8_u.xchg` | 1 byte | nop | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16_s.xchg` | 2 bytes | nop | 2 bytes | sign-extended i16 to i64 |
| `i64.atomic.rmw16_u.xchg` | 2 bytes | nop | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32_s.xchg` | 4 bytes | nop | 4 bytes | sign-extended i32 to i64 |
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
| `i32.atomic.rmw8_s.cmpxchg` | 1 byte | `expected` wrapped from i32 to i8, 8-bit compare equal | wrapped from i32 to i8, store 1 byte | sign-extended from i8 to i32 |
| `i32.atomic.rmw8_u.cmpxchg` | 1 byte | `expected` wrapped from i32 to i8, 8-bit compare equal | wrapped from i32 to i8, store 1 byte | zero-extended from i8 to i32 |
| `i32.atomic.rmw16_s.cmpxchg` | 2 bytes | `expected` wrapped from i32 to i16, 16-bit compare equal | wrapped from i32 to i16, store 2 bytes | sign-extended from i8 to i32 |
| `i32.atomic.rmw16_u.cmpxchg` | 2 bytes | `expected` wrapped from i32 to i16, 16-bit compare equal | wrapped from i32 to i16, store 2 bytes | zero-extended from i8 to i32 |
| `i32.atomic.rmw.cmpxchg` | 4 bytes | 32-bit compare equal | store 4 bytes | as i32 |
| `i64.atomic.rmw8_s.cmpxchg` | 1 byte | `expected` wrapped from i64 to i8, 8-bit compare equal | wrapped from i64 to i8, store 1 byte | sign-extended from i8 to i64 |
| `i64.atomic.rmw8_u.cmpxchg` | 1 byte | `expected` wrapped from i64 to i8, 8-bit compare equal | wrapped from i64 to i8, store 1 byte | zero-extended from i8 to i64 |
| `i64.atomic.rmw16_s.cmpxchg` | 2 bytes | `expected` wrapped from i64 to i16, 16-bit compare equal | wrapped from i64 to i16, store 2 bytes | sign-extended from i16 to i64 |
| `i64.atomic.rmw16_u.cmpxchg` | 2 bytes | `expected` wrapped from i64 to i16, 16-bit compare equal | wrapped from i64 to i16, store 2 bytes | zero-extended from i16 to i64 |
| `i64.atomic.rmw32_s.cmpxchg` | 4 bytes | `expected` wrapped from i64 to i32, 32-bit compare equal | wrapped from i64 to i32, store 4 bytes | sign-extended from i32 to i64 |
| `i64.atomic.rmw32_u.cmpxchg` | 4 bytes | `expected` wrapped from i64 to i32, 32-bit compare equal | wrapped from i64 to i32, store 4 bytes | zero-extended from i32 to i64 |
| `i64.atomic.rmw.cmpxchg` | 8 bytes | 64-bit compare equal | 8 bytes | as i64 |

### Lock-free Guarantees

Only 32-bit atomic accesses are guaranteed to be lock-free. This matches the
[ECMAScript specification](https://tc39.github.io/ecma262/#sec-atomics.islockfree).

### Alignment

Unlike normal memory accesses, misaligned atomic accesses trap. For non-atomic
accesses on shared linear memory, misaligned accesses do not trap.

It is a validation error if the alignment field of the memory access immediate
has any other value than the natural alignment for that access size.

## Thread operators

One new operator is added: `is_lock_free`. It is an optimization primitive.
High-performance algorithms will use `is_lock_free` to determine whether to use
locks or atomic operations in critical sections.

  * `is_lock_free`: given an operand `N` of type `i32`, if the atomic step of an
    atomic primitive (see [Atomic Memory Accesses](#atomic-memory-accesses)) on
    a datum of size `N` bytes will be performed without the [agent][] acquiring
    a lock outside the `N` bytes comprising the datum, then return `1`.
    Otherwise, return `0`. Once the value of `is_lock_free` for a given value
    `N` has been observed for any [agent][] in an [agent cluster][], it cannot
    change.

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

If [HasProperty][]("shared"), then let `shared` be
[ToBoolean][]([Get][](`memoryDescriptor`, "shared")). Otherwise, let `shared`
be `false`.

Let `memory` be the result of calling [Memory.create][] given arguments
`initial`, `maximum`, and `shared`. Note that initial and maximum are specified
in units of WebAssembly pages (64KiB).

Return the result of [CreateMemoryObject][](`memory`).

### `CreateMemoryObject`

Given a [Memory.memory][] `m`, to create a `WebAssembly.Memory`:

If `m` is shared, let `buffer` be a new [SharedArrayBuffer][]. If `m` is not
shared, let `buffer` be a new [ArrayBuffer][]. In either case, `buffer` will
have an internal slot [\[\[ArrayBufferData\]\]][] which aliases `m` and an
internal slot [\[\[ArrayBufferByteLength\]\]][] which is set to the byte length
of `m`.

If `m` is shared, any attempts to [detach][] `buffer` shall throw a
[TypeError][]. Otherwise, any attempts to [detach][] `buffer` _other_ than the
detachment performed by `m.grow` shall throw a [TypeError][].

Return a new `WebAssembly.Memory` instance with [[Memory]] set to `m` and
[[BufferObject]] set to `buffer`.

### `WebAssembly.Memory.prototype.grow`

Let `M` be the `this` value. If `M` is not a `WebAssembly.Memory`, a
[TypeError][] is thrown.

If [IsSharedArrayBuffer][](`M`.\[\[BufferObject\]\]) is false, then this
function behaves as described [here][WebAssembly.Memory.prototype.grow].
Otherwise:

Let `d` be [ToNonWrappingUint32][](`delta`).

Let `ret` be the current size of memory in pages (before resizing).

Perform [Memory.grow][] with delta `d`. On failure, a [RangeError][] is thrown.

Assign to `M.[[BufferObject]]` a new [SharedArrayBuffer][] whose
[\[\[ArrayBufferData\]\]][] aliases `M.[[Memory]]` and whose
[\[\[ArrayBufferByteLength\]\]][] is set to the new byte length of
`M.[[Memory]]`.

Return `ret` as a Number value.

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
          is_lock_free |

          inn.wait memarg |
          wake memarg |

          inn.atomic.load memarg | fnn.atomic.load memarg |
          inn.atomic.store memarg | fnn.atomic.store memarg |
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
        | 0xF0 0x00             =>  is_lock_free

        | 0xF0 0x01 m:memarg32  =>  wake m
        | 0xF0 0x02 m:memarg32  =>  i32.wait m
        | 0xF0 0x03 m:memarg64  =>  i64.wait m

        | 0xF0 0x10 m:memarg32  =>  i32.atomic.rmw.xchg m
        | 0xF0 0x11 m:memarg64  =>  i64.atomic.rmw.xchg m
        | 0xF0 0x12 m:memarg8   =>  i32.atomic.rmw8_s.xchg m
        | 0xF0 0x13 m:memarg8   =>  i32.atomic.rmw8_u.xchg m
        | 0xF0 0x14 m:memarg16  =>  i32.atomic.rmw16_s.xchg m
        | 0xF0 0x15 m:memarg16  =>  i32.atomic.rmw16_u.xchg m
        | 0xF0 0x16 m:memarg8   =>  i64.atomic.rmw8_s.xchg m
        | 0xF0 0x17 m:memarg8   =>  i64.atomic.rmw8_u.xchg m
        | 0xF0 0x18 m:memarg16  =>  i64.atomic.rmw16_s.xchg m
        | 0xF0 0x19 m:memarg16  =>  i64.atomic.rmw16_u.xchg m
        | 0xF0 0x1A m:memarg32  =>  i64.atomic.rmw32_s.xchg m
        | 0xF0 0x1B m:memarg32  =>  i64.atomic.rmw32_u.xchg m

        | 0xF0 0x1C m:memarg32  =>  i32.atomic.rmw.cmpxchg m
        | 0xF0 0x1D m:memarg64  =>  i64.atomic.rmw.cmpxchg m
        | 0xF0 0x1E m:memarg8   =>  i32.atomic.rmw8_s.cmpxchg m
        | 0xF0 0x1F m:memarg8   =>  i32.atomic.rmw8_u.cmpxchg m
        | 0xF0 0x20 m:memarg16  =>  i32.atomic.rmw16_s.cmpxchg m
        | 0xF0 0x21 m:memarg16  =>  i32.atomic.rmw16_u.cmpxchg m
        | 0xF0 0x22 m:memarg8   =>  i64.atomic.rmw8_s.cmpxchg m
        | 0xF0 0x23 m:memarg8   =>  i64.atomic.rmw8_u.cmpxchg m
        | 0xF0 0x24 m:memarg16  =>  i64.atomic.rmw16_s.cmpxchg m
        | 0xF0 0x25 m:memarg16  =>  i64.atomic.rmw16_u.cmpxchg m
        | 0xF0 0x26 m:memarg32  =>  i64.atomic.rmw32_s.cmpxchg m
        | 0xF0 0x27 m:memarg32  =>  i64.atomic.rmw32_u.cmpxchg m

        | 0xF0 0x28 m:memarg32  =>  i32.atomic.load m
        | 0xF0 0x29 m:memarg64  =>  i64.atomic.load m
        | 0xF0 0x2A m:memarg32  =>  f32.atomic.load m
        | 0xF0 0x2B m:memarg64  =>  f64.atomic.load m
        | 0xF0 0x2C m:memarg8   =>  i32.atomic.load8_s m
        | 0xF0 0x2D m:memarg8   =>  i32.atomic.load8_u m
        | 0xF0 0x2E m:memarg16  =>  i32.atomic.load16_s m
        | 0xF0 0x2F m:memarg16  =>  i32.atomic.load16_u m
        | 0xF0 0x30 m:memarg8   =>  i64.atomic.load8_s m
        | 0xF0 0x31 m:memarg8   =>  i64.atomic.load8_u m
        | 0xF0 0x32 m:memarg16  =>  i64.atomic.load16_s m
        | 0xF0 0x33 m:memarg16  =>  i64.atomic.load16_u m
        | 0xF0 0x34 m:memarg32  =>  i64.atomic.load32_s m
        | 0xF0 0x35 m:memarg32  =>  i64.atomic.load32_u m
        | 0xF0 0x36 m:memarg32  =>  i32.atomic.store m
        | 0xF0 0x37 m:memarg64  =>  i64.atomic.store m
        | 0xF0 0x38 m:memarg32  =>  f32.atomic.store m
        | 0xF0 0x39 m:memarg64  =>  f64.atomic.store m
        | 0xF0 0x3A m:memarg8   =>  i32.atomic.store8 m
        | 0xF0 0x3B m:memarg16  =>  i32.atomic.store16 m
        | 0xF0 0x3C m:memarg8   =>  i64.atomic.store8 m
        | 0xF0 0x3D m:memarg16  =>  i64.atomic.store16 m
        | 0xF0 0x3E m:memarg32  =>  i64.atomic.store32 m

        | 0xF0 0x3F m:memarg32  =>  i32.atomic.rmw.add m
        | 0xF0 0x40 m:memarg64  =>  i64.atomic.rmw.add m
        | 0xF0 0x41 m:memarg8   =>  i32.atomic.rmw8_s.add m
        | 0xF0 0x42 m:memarg8   =>  i32.atomic.rmw8_u.add m
        | 0xF0 0x43 m:memarg16  =>  i32.atomic.rmw16_s.add m
        | 0xF0 0x44 m:memarg16  =>  i32.atomic.rmw16_u.add m
        | 0xF0 0x45 m:memarg8   =>  i64.atomic.rmw8_s.add m
        | 0xF0 0x46 m:memarg8   =>  i64.atomic.rmw8_u.add m
        | 0xF0 0x47 m:memarg16  =>  i64.atomic.rmw16_s.add m
        | 0xF0 0x48 m:memarg16  =>  i64.atomic.rmw16_u.add m
        | 0xF0 0x49 m:memarg32  =>  i64.atomic.rmw32_s.add m
        | 0xF0 0x4A m:memarg32  =>  i64.atomic.rmw32_u.add m

        | 0xF0 0x4B m:memarg32  =>  i32.atomic.rmw.sub m
        | 0xF0 0x4C m:memarg64  =>  i64.atomic.rmw.sub m
        | 0xF0 0x4D m:memarg8   =>  i32.atomic.rmw8_s.sub m
        | 0xF0 0x4E m:memarg8   =>  i32.atomic.rmw8_u.sub m
        | 0xF0 0x4F m:memarg16  =>  i32.atomic.rmw16_s.sub m
        | 0xF0 0x50 m:memarg16  =>  i32.atomic.rmw16_u.sub m
        | 0xF0 0x51 m:memarg8   =>  i64.atomic.rmw8_s.sub m
        | 0xF0 0x52 m:memarg8   =>  i64.atomic.rmw8_u.sub m
        | 0xF0 0x53 m:memarg16  =>  i64.atomic.rmw16_s.sub m
        | 0xF0 0x54 m:memarg16  =>  i64.atomic.rmw16_u.sub m
        | 0xF0 0x55 m:memarg32  =>  i64.atomic.rmw32_s.sub m
        | 0xF0 0x56 m:memarg32  =>  i64.atomic.rmw32_u.sub m

        | 0xF0 0x57 m:memarg32  =>  i32.atomic.rmw.and m
        | 0xF0 0x58 m:memarg64  =>  i64.atomic.rmw.and m
        | 0xF0 0x59 m:memarg8   =>  i32.atomic.rmw8_s.and m
        | 0xF0 0x5A m:memarg8   =>  i32.atomic.rmw8_u.and m
        | 0xF0 0x5B m:memarg16  =>  i32.atomic.rmw16_s.and m
        | 0xF0 0x5C m:memarg16  =>  i32.atomic.rmw16_u.and m
        | 0xF0 0x5D m:memarg8   =>  i64.atomic.rmw8_s.and m
        | 0xF0 0x5E m:memarg8   =>  i64.atomic.rmw8_u.and m
        | 0xF0 0x5F m:memarg16  =>  i64.atomic.rmw16_s.and m
        | 0xF0 0x60 m:memarg16  =>  i64.atomic.rmw16_u.and m
        | 0xF0 0x61 m:memarg32  =>  i64.atomic.rmw32_s.and m
        | 0xF0 0x62 m:memarg32  =>  i64.atomic.rmw32_u.and m

        | 0xF0 0x63 m:memarg32  =>  i32.atomic.rmw.or m
        | 0xF0 0x64 m:memarg64  =>  i64.atomic.rmw.or m
        | 0xF0 0x65 m:memarg8   =>  i32.atomic.rmw8_s.or m
        | 0xF0 0x66 m:memarg8   =>  i32.atomic.rmw8_u.or m
        | 0xF0 0x67 m:memarg16  =>  i32.atomic.rmw16_s.or m
        | 0xF0 0x68 m:memarg16  =>  i32.atomic.rmw16_u.or m
        | 0xF0 0x69 m:memarg8   =>  i64.atomic.rmw8_s.or m
        | 0xF0 0x6A m:memarg8   =>  i64.atomic.rmw8_u.or m
        | 0xF0 0x6B m:memarg16  =>  i64.atomic.rmw16_s.or m
        | 0xF0 0x6C m:memarg16  =>  i64.atomic.rmw16_u.or m
        | 0xF0 0x6D m:memarg32  =>  i64.atomic.rmw32_s.or m
        | 0xF0 0x6E m:memarg32  =>  i64.atomic.rmw32_u.or m

        | 0xF0 0x6F m:memarg32  =>  i32.atomic.rmw.xor m
        | 0xF0 0x70 m:memarg64  =>  i64.atomic.rmw.xor m
        | 0xF0 0x71 m:memarg8   =>  i32.atomic.rmw8_s.xor m
        | 0xF0 0x72 m:memarg8   =>  i32.atomic.rmw8_u.xor m
        | 0xF0 0x73 m:memarg16  =>  i32.atomic.rmw16_s.xor m
        | 0xF0 0x74 m:memarg16  =>  i32.atomic.rmw16_u.xor m
        | 0xF0 0x75 m:memarg8   =>  i64.atomic.rmw8_s.xor m
        | 0xF0 0x76 m:memarg8   =>  i64.atomic.rmw8_u.xor m
        | 0xF0 0x77 m:memarg16  =>  i64.atomic.rmw16_s.xor m
        | 0xF0 0x78 m:memarg16  =>  i64.atomic.rmw16_u.xor m
        | 0xF0 0x79 m:memarg32  =>  i64.atomic.rmw32_s.xor m
        | 0xF0 0x7A m:memarg32  =>  i64.atomic.rmw32_u.xor m
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
[HasProperty]: https://tc39.github.io/ecma262/#sec-hasproperty
[ToBoolean]: https://tc39.github.io/ecma262/#sec-toboolean
[Get]: https://tc39.github.io/ecma262/#sec-get-o-p
[Memory.create]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/memory.ml#L47
[Memory.memory]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/memory.mli#L1
[Memory.grow]: https://github.com/WebAssembly/spec/blob/master/interpreter/spec/memory.ml#L60
[SharedArrayBuffer]: https://tc39.github.io/ecma262/#sec-sharedarraybuffer-objects
[detach]: http://tc39.github.io/ecma262/#sec-detacharraybuffer
[TypeError]: https://tc39.github.io/ecma262/#sec-native-error-types-used-in-this-standard-typeerror
[RangeError]: https://tc39.github.io/ecma262/#sec-native-error-types-used-in-this-standard-rangeerror
[\[\[ArrayBufferData\]\]]: http://tc39.github.io/ecma262/#sec-properties-of-the-arraybuffer-prototype-object
[\[\[ArrayBufferByteLength\]\]]: http://tc39.github.io/ecma262/#sec-properties-of-the-arraybuffer-prototype-object
[ToNonWrappingUint32]: https://github.com/WebAssembly/design/blob/master/JS.md#tononwrappinguint32
