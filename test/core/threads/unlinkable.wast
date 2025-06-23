(module $Mem
  (memory (export "shared") 1 1 shared)
)

;; (thread $T1
;;   (module (memory (import "mem" "shared") 1 1 shared))
;; )

(thread $T2
  (assert_unlinkable
    (module (memory (import "mem" "shared") 1 1 shared))
    "unknown import"
  )
)

;; (wait $T1)
(wait $T2)

;; (thread $T3 (shared (module $Mem))
;;   (module (memory (import "mem" "shared") 1 1 shared))
;; )

(thread $T4 (shared (module $Mem))
  (assert_unlinkable
    (module (memory (import "mem" "shared") 1 1 shared))
    "unknown import"
  )
)

;; (wait $T3)
(wait $T4)
