(module $Mem
  (memory (export "shared") 1 1 shared)
)

(thread $T1 (shared (module $Mem))
  (register "mem" $Mem)
  (module
    (memory (import "mem" "shared") 1 10 shared)
    (func (export "run")
      (i32.store (i32.const 0) (i32.const 42))
      (i32.store (i32.const 4) (i32.const 1))
    )
  )
  (invoke "run")
)

(thread $T2 (shared (module $Mem))
  (register "mem" $Mem)
  (module
    (memory (import "mem" "shared") 1 1 shared)
    (func (export "run") (result i32)
      (local i32 i32)
      (i32.load (i32.const 4))
      (local.set 0)
      (i32.load (i32.const 0))
      (local.set 1)
      (i32.or (i32.eq (local.get 0) (i32.const 1)) (i32.eq (local.get 0) (i32.const 0)))
      (i32.or (i32.eq (local.get 1) (i32.const 42)) (i32.eq (local.get 0) (i32.const 0)))
      (i32.and)
      (return)
    )
  )

  (assert_return (invoke "run") (i32.const 1))
)

(wait $T1)
(wait $T2)
