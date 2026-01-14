;; wait/notify
(module
  (memory 1 1 shared)

  (func (export "init") (param $value i64) (i64.store (i32.const 0) (local.get $value)))

  (func (export "memory.atomic.notify") (param $addr i32) (param $count i32) (result i32)
      (memory.atomic.notify (local.get 0) (local.get 1)))
  (func (export "memory.atomic.wait32") (param $addr i32) (param $expected i32) (param $timeout i64) (result i32)
      (memory.atomic.wait32 (local.get 0) (local.get 1) (local.get 2)))
  (func (export "memory.atomic.wait64") (param $addr i32) (param $expected i64) (param $timeout i64) (result i32)
      (memory.atomic.wait64 (local.get 0) (local.get 1) (local.get 2)))
)

(invoke "init" (i64.const 0xffffffffffff))

;; wait returns immediately if values do not match
(assert_return (invoke "memory.atomic.wait32" (i32.const 0) (i32.const 0) (i64.const 0)) (i32.const 1))
(assert_return (invoke "memory.atomic.wait64" (i32.const 0) (i64.const 0) (i64.const 0)) (i32.const 1))

;; wait times out if values do match and timeout is small
(assert_return (invoke "memory.atomic.wait32" (i32.const 0) (i32.const 0xffffffff) (i64.const 10)) (i32.const 2))
(assert_return (invoke "memory.atomic.wait64" (i32.const 0) (i64.const 0xffffffffffff) (i64.const 10)) (i32.const 2))

;; notify always returns
(assert_return (invoke "memory.atomic.notify" (i32.const 0) (i32.const 0)) (i32.const 0))
(assert_return (invoke "memory.atomic.notify" (i32.const 0) (i32.const 10)) (i32.const 0))

;; OOB wait and notify always trap
(assert_trap (invoke "memory.atomic.wait32" (i32.const 65536) (i32.const 0) (i64.const 0)) "out of bounds memory access")
(assert_trap (invoke "memory.atomic.wait64" (i32.const 65536) (i64.const 0) (i64.const 0)) "out of bounds memory access")

;; in particular, notify always traps even if waking 0 threads
(assert_trap (invoke "memory.atomic.notify" (i32.const 65536) (i32.const 0)) "out of bounds memory access")

;; similarly, unaligned wait and notify always trap
(assert_trap (invoke "memory.atomic.wait32" (i32.const 65531) (i32.const 0) (i64.const 0)) "unaligned atomic")
(assert_trap (invoke "memory.atomic.wait64" (i32.const 65524) (i64.const 0) (i64.const 0)) "unaligned atomic")

(assert_trap (invoke "memory.atomic.notify" (i32.const 65531) (i32.const 0)) "unaligned atomic")

;; atomic.wait traps on unshared memory even if it wouldn't block
(module
  (memory 1 1)

  (func (export "init") (param $value i64) (i64.store (i32.const 0) (local.get $value)))

  (func (export "memory.atomic.notify") (param $addr i32) (param $count i32) (result i32)
      (memory.atomic.notify (local.get 0) (local.get 1)))
  (func (export "memory.atomic.wait32") (param $addr i32) (param $expected i32) (param $timeout i64) (result i32)
      (memory.atomic.wait32 (local.get 0) (local.get 1) (local.get 2)))
  (func (export "memory.atomic.wait64") (param $addr i32) (param $expected i64) (param $timeout i64) (result i32)
      (memory.atomic.wait64 (local.get 0) (local.get 1) (local.get 2)))
)

(invoke "init" (i64.const 0xffffffffffff))

(assert_trap (invoke "memory.atomic.wait32" (i32.const 0) (i32.const 0) (i64.const 0)) "expected shared memory")
(assert_trap (invoke "memory.atomic.wait64" (i32.const 0) (i64.const 0) (i64.const 0)) "expected shared memory")

;; notify still works
(assert_return (invoke "memory.atomic.notify" (i32.const 0) (i32.const 0)) (i32.const 0))

;; OOB and unaligned notify still trap
(assert_trap (invoke "memory.atomic.notify" (i32.const 65536) (i32.const 0)) "out of bounds memory access")
(assert_trap (invoke "memory.atomic.notify" (i32.const 65531) (i32.const 0)) "unaligned atomic")

;; test that looping notify eventually unblocks a parallel waiting thread
(module $Mem
  (memory (export "shared") 1 1 shared)
)

(thread $T1 (shared (module $Mem))
  (register "mem" $Mem)
  (module
    (memory (import "mem" "shared") 1 10 shared)
    (func (export "run") (result i32)
      (memory.atomic.wait32 (i32.const 0) (i32.const 0) (i64.const -1))
    )
  )
  ;; test that this thread eventually gets unblocked
  (assert_return (invoke "run") (i32.const 0))
)

(thread $T2 (shared (module $Mem))
  (register "mem" $Mem)
  (module
    (memory (import "mem" "shared") 1 1 shared)
    (func (export "notify-0") (result i32)
      (memory.atomic.notify (i32.const 0) (i32.const 0))
    )
    (func (export "notify-1-while")
      (loop
        (i32.const 1)
        (memory.atomic.notify (i32.const 0) (i32.const 1))
        (i32.ne)
        (br_if 0)
      )
    )
  )
  ;; notifying with a count of 0 will not unblock
  (assert_return (invoke "notify-0") (i32.const 0))
  ;; loop until something is notified
  (assert_return (invoke "notify-1-while"))
)

(wait $T1)
(wait $T2)
