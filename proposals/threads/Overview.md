# Threading proposal for WebAssembly

This page describes a proposal for the post-MVP
[threads feature :atom_symbol:][future threads].

This proposal adds a new shared linear memory type and some new operations for
atomic memory access. The responsibility of creating and joining threads is
deferred to the embedder.

## Example

Here is an example of a naive mutex implemented in WebAssembly. It uses one
i32 in linear memory to store the state of the lock. If its value is 0, the
mutex is unlocked. If its value is 1, the mutex is locked.

```wasm
(module
  ;; Import 1 page (64Kib) of shared memory.
  (import "env" "memory" (memory 1 1 shared))

  ;; Try to lock a mutex at the given address.
  ;; Returns 1 if the mutex was successfully locked, and 0 otherwise.
  (func $tryLockMutex (export "tryLockMutex")
    (param $mutexAddr i32) (result i32)
    ;; Attempt to grab the mutex. The cmpxchg operation atomically
    ;; does the following:
    ;; - Loads the value at $mutexAddr.
    ;; - If it is 0 (unlocked), set it to 1 (locked).
    ;; - Return the originally loaded value.
    (i32.atomic.rmw.cmpxchg
      (local.get $mutexAddr) ;; mutex address
      (i32.const 0)          ;; expected value (0 => unlocked)
      (i32.const 1))         ;; replacement value (1 => locked)

    ;; The top of the stack is the originally loaded value.
    ;; If it is 0, this means we acquired the mutex. We want to
    ;; return the inverse (1 means mutex acquired), so use i32.eqz
    ;; as a logical not.
    (i32.eqz)
  )

  ;; Lock a mutex at the given address, retrying until successful.
  (func (export "lockMutex")
    (param $mutexAddr i32)
    (block $done
      (loop $retry
        ;; Try to lock the mutex. $tryLockMutex returns 1 if the mutex
        ;; was locked, and 0 otherwise.
        (call $tryLockMutex (local.get $mutexAddr))
        (br_if $done)

        ;; Wait for the other agent to finish with mutex.
        (memory.atomic.wait32
          (local.get $mutexAddr) ;; mutex address
          (i32.const 1)          ;; expected value (1 => locked)
          (i64.const -1))        ;; infinite timeout

        ;; memory.atomic.wait32 returns:
        ;;   0 => "ok", woken by another agent.
        ;;   1 => "not-equal", loaded value != expected value
        ;;   2 => "timed-out", the timeout expired
        ;;
        ;; Since there is an infinite timeout, only 0 or 1 will be returned. In
        ;; either case we should try to acquire the mutex again, so we can
        ;; ignore the result.
        (drop)

        ;; Try to acquire the lock again.
        (br $retry)
      )
    )
  )

  ;; Unlock a mutex at the given address.
  (func (export "unlockMutex")
    (param $mutexAddr i32)
    ;; Unlock the mutex.
    (i32.atomic.store
      (local.get $mutexAddr)     ;; mutex address
      (i32.const 0))             ;; 0 => unlocked

    ;; Notify one agent that is waiting on this lock.
    (drop
      (memory.atomic.notify
        (local.get $mutexAddr)   ;; mutex address
        (i32.const 1)))          ;; notify 1 waiter
  )
)
```

Here is an example of using this module in a JavaScript host.

```JavaScript
/// main.js ///
let moduleBytes = ...;  // An ArrayBuffer containing the WebAssembly module above.
let memory = new WebAssembly.Memory({initial: 1, maximum: 1, shared: true});
let worker = new Worker('worker.js');
const mutexAddr = 0;

// Send the shared memory to the worker.
worker.postMessage(memory);

let imports = {env: {memory: memory}};
let module = WebAssembly.instantiate(moduleBytes, imports).then(
    ({instance}) => {
        // Blocking on the main thread is not allowed, so we can't
        // call lockMutex.
        if (instance.exports.tryLockMutex(mutexAddr)) {
            ...
            instance.exports.unlockMutex(mutexAddr);
        }
    });


/// worker.js ///
let moduleBytes = ...;  // An ArrayBuffer containing the WebAssembly module above.
const mutexAddr = 0;

// Listen for messages from the main thread.
onmessage = function(e) {
    let memory = e.data;
    let imports = {env: {memory: memory}};
    let module = WebAssembly.instantiate(moduleBytes, imports).then(
        ({instance}) => {
            // Blocking on a Worker thread is allowed.
            instance.exports.lockMutex(mutexAddr);
            ...
            instance.exports.unlockMutex(mutexAddr);
        });
};
```

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

```wasm
;; Data module
(module $data_module
  (memory (export "memory") 1)
  (data (i32.const 0) "..."))

;; Main module
(module $main_module
  (import "env" "memory" (memory 1))
  ...)
```
```js
WebAssembly.instantiate(dataModuleBytes, {}).then(
    ({instance}) => {
        let imports = {env: {memory: instance.exports.memory}};
        WebAssembly.instantiate(mainModuleBytes, imports).then(...);
    });
```

## Import/Export Mutable Globals

This has been separated into
[its own proposal](https://github.com/WebAssembly/mutable-global/).

## New Sign-extending Operators

This has been separated into
[its own proposal](https://github.com/WebAssembly/sign-extension-ops/).

## Atomic Memory Accesses

Atomic memory accesses are separated into three categories, load/store,
read-modify-write, and compare-exchange. All atomic memory accesses can be
performed on both shared and unshared linear memories.

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
| `i32.atomic.rmw8.add_u` | 1 byte | 8-bit sign-agnostic addition | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16.add_u` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.add` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | as i32 |
| `i64.atomic.rmw8.add_u` | 1 byte | 8-bit sign-agnostic addition | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16.add_u` | 2 bytes | 16-bit sign-agnostic addition | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32.add_u` | 4 bytes | 32-bit sign-agnostic addition | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.add` | 8 bytes | 64-bit sign-agnostic addition | 8 bytes | as i64 |
| `i32.atomic.rmw8.sub_u` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16.sub_u` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.sub` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | as i32 |
| `i64.atomic.rmw8.sub_u` | 1 byte | 8-bit sign-agnostic subtraction | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16.sub_u` | 2 bytes | 16-bit sign-agnostic subtraction | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32.sub_u` | 4 bytes | 32-bit sign-agnostic subtraction | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.sub` | 8 bytes | 64-bit sign-agnostic subtraction | 8 bytes | as i64 |
| `i32.atomic.rmw8.and_u` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16.and_u` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.and` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | as i32 |
| `i64.atomic.rmw8.and_u` | 1 byte | 8-bit sign-agnostic bitwise and | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16.and_u` | 2 bytes | 16-bit sign-agnostic bitwise and | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32.and_u` | 4 bytes | 32-bit sign-agnostic bitwise and | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.and` | 8 bytes | 64-bit sign-agnostic bitwise and | 8 bytes | as i64 |
| `i32.atomic.rmw8.or_u` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16.or_u` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.or` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | as i32 |
| `i64.atomic.rmw8.or_u` | 1 byte | 8-bit sign-agnostic bitwise inclusive or | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16.or_u` | 2 bytes | 16-bit sign-agnostic bitwise inclusive or | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32.or_u` | 4 bytes | 32-bit sign-agnostic bitwise inclusive or | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.or` | 8 bytes | 64-bit sign-agnostic bitwise inclusive or | 8 bytes | as i64 |
| `i32.atomic.rmw8.xor_u` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16.xor_u` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.xor` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | as i32 |
| `i64.atomic.rmw8.xor_u` | 1 byte | 8-bit sign-agnostic bitwise exclusive or | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16.xor_u` | 2 bytes | 16-bit sign-agnostic bitwise exclusive or | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32.xor_u` | 4 bytes | 32-bit sign-agnostic bitwise exclusive or | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.xor` | 8 bytes | 64-bit sign-agnostic bitwise exclusive or | 8 bytes | as i64 |
| `i32.atomic.rmw8.xchg_u` | 1 byte | nop | 1 byte | zero-extended i8 to i32 |
| `i32.atomic.rmw16.xchg_u` | 2 bytes | nop | 2 bytes | zero-extended i16 to i32 |
| `i32.atomic.rmw.xchg` | 4 bytes | nop | 4 bytes | as i32 |
| `i64.atomic.rmw8.xchg_u` | 1 byte | nop | 1 byte | zero-extended i8 to i64 |
| `i64.atomic.rmw16.xchg_u` | 2 bytes | nop | 2 bytes | zero-extended i16 to i64 |
| `i64.atomic.rmw32.xchg_u` | 4 bytes | nop | 4 bytes | zero-extended i32 to i64 |
| `i64.atomic.rmw.xchg` | 8 bytes | nop | 8 bytes | as i64 |


### Compare Exchange

The atomic compare exchange operators take three operands: an address, an
`expected` value, and a `replacement` value. If the `loaded` value is equal to
the `expected` value, the `replacement` value is stored to the same memory
address. If the values are not equal, no value is stored. In either case, the
`loaded` value is returned.

| Name | Load (as `loaded`) | Compare `expected` with `loaded` | Conditionally Store `replacement` | Return `loaded` |
| ---- | ---- | ---- | ---- | ---- |
| `i32.atomic.rmw8.cmpxchg_u` | 1 byte | `expected` wrapped from i32 to i8, 8-bit compare equal | wrapped from i32 to i8, store 1 byte | zero-extended from i8 to i32 |
| `i32.atomic.rmw16.cmpxchg_u` | 2 bytes | `expected` wrapped from i32 to i16, 16-bit compare equal | wrapped from i32 to i16, store 2 bytes | zero-extended from i8 to i32 |
| `i32.atomic.rmw.cmpxchg` | 4 bytes | 32-bit compare equal | store 4 bytes | as i32 |
| `i64.atomic.rmw8.cmpxchg_u` | 1 byte | `expected` wrapped from i64 to i8, 8-bit compare equal | wrapped from i64 to i8, store 1 byte | zero-extended from i8 to i64 |
| `i64.atomic.rmw16.cmpxchg_u` | 2 bytes | `expected` wrapped from i64 to i16, 16-bit compare equal | wrapped from i64 to i16, store 2 bytes | zero-extended from i16 to i64 |
| `i64.atomic.rmw32.cmpxchg_u` | 4 bytes | `expected` wrapped from i64 to i32, 32-bit compare equal | wrapped from i64 to i32, store 4 bytes | zero-extended from i32 to i64 |
| `i64.atomic.rmw.cmpxchg` | 8 bytes | 64-bit compare equal | 8 bytes | as i64 |

### Alignment

Unlike normal memory accesses, misaligned atomic accesses trap. For non-atomic
accesses on shared linear memory, misaligned accesses do not trap.

It is a validation error if the alignment field of the memory access immediate
has any other value than the natural alignment for that access size.

## Wait and Notify operators

The notify and wait operators are optimizations over busy-waiting for a value
to change. The operators have sequentially consistent ordering.

Both notify and wait operators trap if the effective address of either operator
is misaligned or out-of-bounds. Wait operators additionally trap if used on an
unshared linear memory. The wait operators require an alignment of their memory
access size. The notify operator requires an alignment of 32 bits.

For the web embedding, the agent can also be suspended or woken via the
[`Atomics.wait`][] and [`Atomics.notify`][] functions respectively. An agent
will not be suspended for other reasons, unless all agents in that cluster are
also suspended.

An agent suspended via `Atomics.wait` can be woken by the WebAssembly
`memory.atomic.notify` operator. Similarly, an agent suspended by
`memory.atomic.wait32` or `memory.atomic.wait64` can be woken by
[`Atomics.notify`][].

### Wait

The wait operator take three operands: an address operand, an expected value,
and a relative timeout in nanoseconds as an `i64`. The return value is `0`,
`1`, or `2`, returned as an `i32`.

| `timeout` value | Behavior |
| ---- | ---- |
| `timeout` < 0 | Never expires |
| 0 <= `timeout` <= maximum signed i64 value | Expires after `timeout` nanoseconds |

| Return value | Description |
| ---- | ---- |
| `0` | "ok", woken by another agent in the cluster |
| `1` | "not-equal", the loaded value did not match the expected value |
| `2` | "timed-out", not woken before timeout expired |

If the linear memory is unshared, the wait operation traps. Otherwise, the wait
operation begins by performing an atomic load from the given address.  If the
loaded value is not equal to the expected value, the operator returns 1
("not-equal"). If the values are equal, the agent is suspended. If the agent is
woken, the wait operator returns 0 ("ok"). If the timeout expires before another
agent notifies this one, this operator returns 2 ("timed-out"). Note that when
the agent is suspended, it will not be [spuriously
woken](https://en.wikipedia.org/wiki/Spurious_wakeup).  The agent is only woken
by `memory.atomic.notify` (or [`Atomics.notify`][] in the web embedding).

When an agent is suspended, if the number of waiters (including this one) is
equal to 2<sup>32</sup>, then trap.

  * `memory.atomic.wait32`: load i32 value, compare to expected (as `i32`), and wait for notify at same address
  * `memory.atomic.wait64`: load i64 value, compare to expected (as `i64`), and wait for notify at same address

For the web embedding, `memory.atomic.wait32` is equivalent in behavior to executing the following:

1. Let `memory` be a `WebAssembly.Memory` object for this module.
1. Let `buffer` be `memory`([`Get`][](`memory`, `"buffer"`)).
1. Let `int32array` be [`Int32Array`][](`buffer`).
1. Let `result` be [`Atomics.wait`][](`int32array`, `address`, `expected`, `timeout` / 1e6),
   where `address`, `expected`, and `timeout` are the operands to the `wait` operator
   as described above.
1. Return an `i32` value as described in the above table:
   ("ok" -> `0`, "not-equal" -> `1`, "timed-out" -> `2`).

Similarly, `memory.atomic.wait64` is equivalent in behavior to executing the following:

1. Let `memory` be a `WebAssembly.Memory` object for this module.
1. Let `buffer` be `memory`([`Get`][](`memory`, `"buffer"`)).
1. Let `int64array` be `BigInt64Array`[](`buffer`)
1. Let `result` be [`Atomics.wait`][](`int64array`, `address`, `expected`, `timeout` / 1e6),
   where `address`, `expected`, and `timeout` are the operands to the `wait` operator
   as described above.
1. Return an `i32` value as described in the above table:
   ("ok" -> `0`, "not-equal" -> `1`, "timed-out" -> `2`).

### Notify

The notify operator takes two operands: an address operand and a count as an
unsigned `i32`. The operation will notify as many waiters as are waiting on the
same effective address, up to the maximum as specified by `count`. The operator
returns the number of waiters that were woken as an unsigned `i32`. Note that
there is no way to create a waiter on unshared linear memory from within Wasm,
so if the notify operator is used with an unshared linear memory, the number of
waiters will always be zero unless the host has created such a waiter.

  * `memory.atomic.notify`: notify `count` threads waiting on the given address via `memory.atomic.wait32` or `memory.atomic.wait64`

For the web embedding, `memory.atomic.notify` is equivalent in behavior to executing the following:

1. Let `memory` be a `WebAssembly.Memory` object for this module.
1. Let `buffer` be `memory`([`Get`][](`memory`, `"buffer"`)).
1. Let `int32array` be [`Int32Array`][](`buffer`).
1. Let `result` be [`Atomics.notify`][](`int32array`, `address`, `count`).
1. Return `result` converted to an `i32`.

## Fence operator

The fence operator, `atomic.fence`, takes no operands, and returns nothing. It is intended to preserve the synchronization guarantees of the [fence operators of higher-level languages](https://en.cppreference.com/w/cpp/atomic/atomic_thread_fence).

Unlike other atomic operators, `atomic.fence` does not target a particular linear memory. It may occur in modules which declare no memory without causing a validation error.

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

Note: When [`IsSharedArrayBuffer`][](`M.[[BufferObject]]`) is true, the return
value should be the result of an atomic read-modify-write of the new size
to the internal [\[\[ArrayBufferByteLength\]\]][] slot. The `ret` value will be
the value in pages read from the internal [\[\[ArrayBufferByteLength\]\]][] slot 
before the modification to the resized size, which will be the current size of
the memory.

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

Note: Freezing the buffer prevents storing properties on the buffer object,
which will be lost when the cached buffer is invalidated. The buffer will
be invalidated whenever its size changes, and this can happen at any time
on another thread that has access to the shared buffer.

## [Spec Changes][spec]

The [limits type][] now has an additional field specifying whether
the linear memory or table is shared:

```
limits ::= {min u32, max u32?, share}
share  ::= unshared | shared
```

Its [encoding][limits encoding] is as follows:

```
limits ::= 0x00 n:u32          => {min n, max e, unshared}
           0x01 n:u32 m:u32    => {min n, max m, unshared}
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
          memory.atomic.wait{nn} memarg |
          memory.atomic.notify memarg |

          atomic.fence |

          inn.atomic.load memarg | inn.atomic.store memarg |
          inn.atomic.load8_u memarg | inn.atomic.load16_u memarg | i64.atomic.load32_u memarg |
          inn.atomic.store8 memarg | inn.atomic.store16 memarg | i64.atomic.store32 memarg |

          inn.atomic.rmw.atomicop memarg |
          inn.atomic.rmw8.atomicop_u memarg |
          inn.atomic.rmw16.atomicop_u memarg |
          i64.atomic.rmw32.atomicop_u memarg |
```

The [instruction binary format][] is modified as follows:

```
memarg8  ::= 0x00 o: offset     =>  {align 0, offset: o}
memarg16 ::= 0x01 o: offset     =>  {align 1, offset: o}
memarg32 ::= 0x02 o: offset     =>  {align 2, offset: o}
memarg64 ::= 0x03 o: offset     =>  {align 3, offset: o}

instr ::= ...
        | 0xFE 0x00 m:memarg32  =>  memory.atomic.notify m
        | 0xFE 0x01 m:memarg32  =>  memory.atomic.wait32 m
        | 0xFE 0x02 m:memarg64  =>  memory.atomic.wait64 m

        | 0xFE 0x03 0x00        =>  atomic.fence

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
        | 0xFE 0x20 m:memarg8   =>  i32.atomic.rmw8.add_u m
        | 0xFE 0x21 m:memarg16  =>  i32.atomic.rmw16.add_u m
        | 0xFE 0x22 m:memarg8   =>  i64.atomic.rmw8.add_u m
        | 0xFE 0x23 m:memarg16  =>  i64.atomic.rmw16.add_u m
        | 0xFE 0x24 m:memarg32  =>  i64.atomic.rmw32.add_u m

        | 0xFE 0x25 m:memarg32  =>  i32.atomic.rmw.sub m
        | 0xFE 0x26 m:memarg64  =>  i64.atomic.rmw.sub m
        | 0xFE 0x27 m:memarg8   =>  i32.atomic.rmw8.sub_u m
        | 0xFE 0x28 m:memarg16  =>  i32.atomic.rmw16.sub_u m
        | 0xFE 0x29 m:memarg8   =>  i64.atomic.rmw8.sub_u m
        | 0xFE 0x2A m:memarg16  =>  i64.atomic.rmw16.sub_u m
        | 0xFE 0x2B m:memarg32  =>  i64.atomic.rmw32.sub_u m

        | 0xFE 0x2C m:memarg32  =>  i32.atomic.rmw.and m
        | 0xFE 0x2D m:memarg64  =>  i64.atomic.rmw.and m
        | 0xFE 0x2E m:memarg8   =>  i32.atomic.rmw8.and_u m
        | 0xFE 0x2F m:memarg16  =>  i32.atomic.rmw16.and_u m
        | 0xFE 0x30 m:memarg8   =>  i64.atomic.rmw8.and_u m
        | 0xFE 0x31 m:memarg16  =>  i64.atomic.rmw16.and_u m
        | 0xFE 0x32 m:memarg32  =>  i64.atomic.rmw32.and_u m

        | 0xFE 0x33 m:memarg32  =>  i32.atomic.rmw.or m
        | 0xFE 0x34 m:memarg64  =>  i64.atomic.rmw.or m
        | 0xFE 0x35 m:memarg8   =>  i32.atomic.rmw8.or_u m
        | 0xFE 0x36 m:memarg16  =>  i32.atomic.rmw16.or_u m
        | 0xFE 0x37 m:memarg8   =>  i64.atomic.rmw8.or_u m
        | 0xFE 0x38 m:memarg16  =>  i64.atomic.rmw16.or_u m
        | 0xFE 0x39 m:memarg32  =>  i64.atomic.rmw32.or_u m

        | 0xFE 0x3A m:memarg32  =>  i32.atomic.rmw.xor m
        | 0xFE 0x3B m:memarg64  =>  i64.atomic.rmw.xor m
        | 0xFE 0x3C m:memarg8   =>  i32.atomic.rmw8.xor_u m
        | 0xFE 0x3D m:memarg16  =>  i32.atomic.rmw16.xor_u m
        | 0xFE 0x3E m:memarg8   =>  i64.atomic.rmw8.xor_u m
        | 0xFE 0x3F m:memarg16  =>  i64.atomic.rmw16.xor_u m
        | 0xFE 0x40 m:memarg32  =>  i64.atomic.rmw32.xor_u m

        | 0xFE 0x41 m:memarg32  =>  i32.atomic.rmw.xchg m
        | 0xFE 0x42 m:memarg64  =>  i64.atomic.rmw.xchg m
        | 0xFE 0x43 m:memarg8   =>  i32.atomic.rmw8.xchg_u m
        | 0xFE 0x44 m:memarg16  =>  i32.atomic.rmw16.xchg_u m
        | 0xFE 0x45 m:memarg8   =>  i64.atomic.rmw8.xchg_u m
        | 0xFE 0x46 m:memarg16  =>  i64.atomic.rmw16.xchg_u m
        | 0xFE 0x47 m:memarg32  =>  i64.atomic.rmw32.xchg_u m

        | 0xFE 0x48 m:memarg32  =>  i32.atomic.rmw.cmpxchg m
        | 0xFE 0x49 m:memarg64  =>  i64.atomic.rmw.cmpxchg m
        | 0xFE 0x4A m:memarg8   =>  i32.atomic.rmw8.cmpxchg_u m
        | 0xFE 0x4B m:memarg16  =>  i32.atomic.rmw16.cmpxchg_u m
        | 0xFE 0x4C m:memarg8   =>  i64.atomic.rmw8.cmpxchg_u m
        | 0xFE 0x4D m:memarg16  =>  i64.atomic.rmw16.cmpxchg_u m
        | 0xFE 0x4E m:memarg32  =>  i64.atomic.rmw32.cmpxchg_u m
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
[`Memory.create`]: https://github.com/WebAssembly/spec/blob/master/interpreter/runtime/memory.ml#L26
[`Memory.memory`]: https://github.com/WebAssembly/spec/blob/master/interpreter/runtime/memory.ml#L10
[`Memory.grow`]: https://github.com/WebAssembly/spec/blob/master/interpreter/runtime/memory.ml#L48
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
[`Atomics.notify`]: https://tc39.github.io/ecma262/#sec-atomics.notify
[`Int32Array`]: https://tc39.github.io/ecma262/#sec-typedarray-objects
