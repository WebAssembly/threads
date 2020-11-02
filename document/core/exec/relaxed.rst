.. todo:: add index entries

.. index:: ! relaxed memory, memory
.. _relaxed:

Relaxed Memory Model
--------------------

.. todo:: intro, cite [#cite-oopsla2019]_
.. todo:: link this section with operational semantics


.. _relaxed-trace:

Traces
~~~~~~

.. todo:: define, explain


.. _relaxed-consistent:

Consistency
~~~~~~~~~~~

.. todo:: define auxiliary functions (either here or in Runtime Structure)

.. todo:: add prose intuition

.. math::
   \frac{
     \forall r, \, \vdash_r \X{tr} \consistentwith
   }{
     \vdash \X{tr} \consistent
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{}}
       \forall \evt_R \in \F{reading}_r(\X{tr}), \exists \evt_W^\ast,
         \X{tr} \vdash_r \evt_R \readseachfrom \evt_W^\ast \\
       \forall \evt_I, \evt \in \X{tr}, \,
         \F{ord}_r(\evt_I) = \INIT \wedge
         \evt_I \neq \evt \wedge
         \F{overlap}_r(\evt_I, \evt) \Rightarrow \evt_I \prechb \evt
     \end{array}
   }{
     \vdash_r \X{tr} \consistentwith
   }

.. math::
   \frac{
     \begin{array}[b]{@{}c@{}}
       \left|\evt_W^\ast\right| = |\F{read}_r(\evt_R)| \\
       \forall i < |\evt_W^\ast|,
         \X{tr} \vdash_r^i \evt_R \readsfrom \left(\evt_W^\ast[i]\right)
       \\
       \vdash_r \evt_R \notear \evt_W^\ast
     \end{array}
   }{
     \X{tr} \vdash_r \evt_R \readseachfrom \evt_W^\ast
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{}}
       \evt_R \neq \evt_W \\
       \evt_W \in \F{writing}_r(\X{tr})
     \end{array}
     \qquad
     \begin{array}[b]{@{}r@{}}
       \X{tr} \vdash_r^{i,k} \evt_R \valueconsistent \evt_W \\
       \X{tr} \vdash_r^k \evt_R \hbconsistent \evt_W
     \end{array}
     \qquad
     \X{tr} \vdash_r \evt_R \sclastvisible \evt^\ast_W
   }{
     \X{tr} \vdash_r^i \evt_R \readsfrom \evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{@{}r@{~}c@{~}l@{}}
       \F{read}_r(\evt_R)[i] &=& \F{write}_r(\evt_W)[j] \\
       k = \F{offset}_r(\evt_R) + i &=& \F{offset}_r(\evt_W) + j
     \end{array}
  }{
     \X{tr} \vdash_r^{i,k} \evt_R \valueconsistent \evt_W
  }

.. math::
   \frac{
     \begin{array}[b]{@{}c}
       \neg (\evt_R \prechb \evt_W) \\
       \F{sync}_r(\evt_W, \evt_R) \Rightarrow \evt_W \prechb \evt_R
     \end{array}
    \qquad
    \begin{array}[b]{@{}l@{}}
      \forall \evt'_W \in \F{writing}_r(\X{tr}),\\
      \quad \evt_W \prechb \evt'_W \prechb \evt_R \Rightarrow k \notin \F{range}_r(\evt'_W)
    \end{array}
   }{
    \X{tr} \vdash_r^k \evt_R \hbconsistent \evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{\qquad}l@{}}
       \forall \evt'_W \in \F{writing}_r(\X{tr}), \evt_W \prechb \evt_R \Rightarrow \\
       \quad \evt_W \prectot \evt'_W \prectot \evt_R \wedge \F{sync}_r(\evt_W, \evt_R) \Rightarrow \neg \F{sync}_r(\evt'_W, \evt_R) \\
       \quad \evt_W \prechb \evt'_W \prectot \evt_R  \Rightarrow \neg\F{sync}_r(\evt'_W, \evt_R) \\
       \quad \evt_W \prectot \evt'_W \prechb \evt_R \Rightarrow \neg\F{sync}_r(\evt_W, \evt'_W)
     \end{array}
   }{
     \X{tr} \vdash_r \evt_R \sclastvisible \evt_W
   }

.. math::
   \frac{
     \F{tearfree}_r(\evt_R) \Rightarrow |\{\evt_W \in \evt_W^\ast ~|~ \F{same}_r(\evt_R, \evt_W) \wedge \F{tearfree}_r(\evt_W)\}| \leq 1
   }{
     \vdash_r \evt_R \notear \evt_W^\ast
   }


.. [#cite-oopsla2019]
   The semantics of the relaxed memory model is derived from the following article:
   Conrad Watt, Andreas Rossberg, Jean Pichon-Pharabod. |OOPSLA2019|_. Proceedings of the ACM on Programming Languages (OOPSLA 2019). ACM 2019.
