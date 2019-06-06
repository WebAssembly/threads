Relaxed Memory Model
--------------------

.. todo:: link this section with operational semantics

.. todo:: define auxiliary functions (either here or in Runtime Structure)

.. todo:: add prose intuition

.. math::
   \frac{
     \forall r, \, \vdash_r \X{tr} \validwith
   }{
     \vdash \X{tr} \valid
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{}}
       \forall \evt_R \in \F{reading}_r(\X{tr}), \exists \evt_W^\ast, \X{tr} \vdash_r \evt_R \readseachfrom \evt_W^\ast \\
       \forall \evt_I, \evt \in \X{tr}, \, \F{ord}_r(\evt_I) = \INIT \wedge \evt_I \neq \evt \wedge \F{overlap}_r(\evt_I, \evt) \Rightarrow \evt_I \hbprec \evt
     \end{array}
   }{
     \vdash_r \X{tr} \validwith
   }

.. math::
   \frac{
     \begin{array}[b]{@{}c@{}}
       \left|\evt_W^\ast\right| = |\F{read}_r(\evt_R)| \\
       \forall i < |\evt_W^\ast|, \X{tr} \vdash_r^i \evt_R \readsfrom \left(\evt_W^\ast[i]\right)
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
       \neg (\evt_R \hbprec \evt_W) \\
       \F{sync}_r(\evt_W, \evt_R) \Rightarrow \evt_W \hbprec \evt_R
     \end{array}
    \qquad
    \begin{array}[b]{@{}l@{}}
      \forall \evt'_W \in \F{writing}_r(\X{tr}),\\
      \quad \evt_W \hbprec \evt'_W \hbprec \evt_R \Rightarrow k \notin \F{range}_r(\evt'_W)
    \end{array}
   }{
    \X{tr} \vdash_r^k \evt_R \hbconsistent \evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{\qquad}l@{}}
       \forall \evt'_W \in \F{writing}_r(\X{tr}), \evt_W \hbprec \evt_R \Rightarrow \\
       \quad \evt_W \totprec \evt'_W \totprec \evt_R \wedge \F{sync}_r(\evt_W, \evt_R) \Rightarrow \neg \F{sync}_r(\evt'_W, \evt_R) \\
       \quad \evt_W \hbprec \evt'_W \totprec \evt_R  \Rightarrow \neg\F{sync}_r(\evt'_W, \evt_R) \\
       \quad \evt_W \totprec \evt'_W \hbprec \evt_R \Rightarrow \neg\F{sync}_r(\evt_W, \evt'_W)
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
