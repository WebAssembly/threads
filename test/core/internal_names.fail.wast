;; There's an anologous problem with thread names
;; if we name a thread $_T1, etc.

(module $_M1
  (func (export "run")
    (local i32)
    (i32.const 1)
    (local.set 0)
  )
)
(invoke "run")
