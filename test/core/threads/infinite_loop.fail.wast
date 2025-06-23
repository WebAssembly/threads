(module $Mem
  (memory (export "shared") 1 1 shared)
)
(register "mem")

(thread $Loop (shared (module $Mem))
  (register "mem" $Mem)
  (module
    (memory (import "mem" "shared") 1 1 shared)
    (func (export "run")
      (loop $inf_loop
        (i32.store (i32.const 5) (i32.const 42))
        (br $inf_loop)
      )
    )
  )
  (invoke "run")
)


;; (wait $Loop)

(module $Check
  (memory (import "mem" "shared") 1 1 shared)

  (func (export "check") (result i32)
    (i32.load (i32.const 5))
    (return)
  )
)

(assert_return (invoke $Check "check") (i32.const 42))
