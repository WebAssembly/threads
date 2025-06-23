(module $M1
    (func (export "run") (result i32)
        (local i32)
        (i32.const 1)
        (local.set 0)
        (local.get 0)
        (return)
    )
)

(module $M1
    (func (export "run") (result i32)
        (local i32)
        (i32.const 2)
        (local.set 0)
        (local.get 0)
        (return)
    )
)

(assert_return (invoke $M1 "run") (i32.const 2))
