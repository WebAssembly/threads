.. todo:: add index entries

.. index:: ! relaxed memory, memory
.. _relaxed:

Relaxed Memory Model
--------------------

The execution of a WebAssembly program gives rise to a :ref:`trace <relaxed-trace>` of events. WebAssembly's relaxed memory model constrains the observable behaviours of the program's execution by defining a :ref:`consistency <relaxed-consistent>` condition on the trace of events.

.. note::
   A relaxed memory model is necessary to describe the behaviour of programs exhibiting *shared memory concurrency*.
   WebAssembly's relaxed memory model is heavily based on those of C/C++11 and JavaScript.
   The relaxed memory model decribed here is derived from the following article: [#cite-oopsla2019]_.


.. _relaxed-aux:

Preliminary Definitions
~~~~~~~~~~~~~~~~~~~~~~~

Bla bla


.. _relaxed-trace:

Traces
~~~~~~

.. todo:: novel notation here?

A trace is a coinductive set of :ref:`events <syntax-evt>`. A trace is considered to be a *pre-execution* of a given :ref:`global configuration <syntax-config>` if it can be derived from the events emitted by the coinductive closure of the :ref:`global reduction relation <syntax-reduction>` on that configuration, and all the :ref:`time stamps <syntax-time>` of its constituent events are distinct.

.. math::
   \frac{
     \config \stepto^{\evt} \config' \qquad \vdash \config' : \trace \qquad \timeevt(\evt) \notin \timeevt^\ast(\trace)
   }{
     \vdash \config : \evt~\trace
   }

When a WebAssembly program is executed, all behaviours observed during that execution must correspond to a single :ref:`consistent <relaxed-consistent>` pre-execution of that execution's starting :ref:`configuration <syntax-config>`.


.. _relaxed-consistent:

Consistency
~~~~~~~~~~~

.. todo:: define auxiliary functions (either here or in Runtime Structure)

.. math::
   \begin{array}{lcl}
   \ordaux(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \ord \\
   \ordaux(\AWR_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \ord \\
   \ordaux(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)   & = & \SEQCST \\
   &&\\
   \locaux(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \loc \\
   \locaux(\AWR_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \loc \\
   \locaux(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)   & = & \loc \\
   &&\\
   \sizeaux(\ARD_{\ord}~\loc~\byte^n~\NOTEARS^?)       & = & n \\
   \sizeaux(\AWR_{\ord}~\loc~\byte^n~\NOTEARS^?)       & = & n \\
   \sizeaux(\ARMW~\loc~{\byte_1}^n~{\byte_2}^n)        & = & n \\
   &&\\
   \readaux(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)    & = & \byte^\ast \\
   \readaux(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)  & = & {\byte_1}^\ast \\
   \readaux(\act)  & = & \epsilon \qquad \otherwise \\
   &&\\
   \writeaux(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)   & = & \epsilon \\
   \writeaux(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast) & = & {\byte_2}^\ast \\
   \writeaux(\act)  & = & \epsilon \qquad \otherwise \\
   &&\\
   \addraux(\act)       & = & \addraux(\regionaux(\act) \\
   \addraux(\loc)       & = & \addraux(\regionaux(\reg) \\
   \addraux(\addr.\fld) & = & \addr \\
   &&\\
   \regionaux(\act)     & = & \regionaux(\locaux(\act) \\
   \regionaux(\reg)     & = & \reg \\
   \regionaux(\reg[i])  & = & \reg \\
   &&\\
   \offsetaux(\act)    & = & \offsetact(\locaux(\act)) \\
   \offsetaux(\reg)    & = & 0 \\
   \offsetaux(\reg[i]) & = & i \\
   \end{array}

.. math::
   \begin{array}{rcl}
   \timeevt(\act^\ast~\AT~\time)     & = & \time \\
   \\
   \ordact(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \ord \\
   \ordact(\AWR_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \ord \\
   \ordact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)   & = & \SEQCST \\
   \\
   \overlapact(\act_1, \act_2) \ldots  & = & \rangeact(\act_1) \cup \rangeact(\act_2) \neq \epsilon  \\
   \sameact \ldots & = & \rangeact(\act_1) = \rangeact(\act_2) \\
   \\
   \readingact(\act)     & = & \readact(\act) \neq \epsilon \\
   \writingact(\act)     & = & \writeact(\act) \neq \epsilon \\
   \\
   \readact(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)    & = & \byte^\ast \\
   \readact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)  & = & {\byte_1}^\ast \\
   \readact(\act)  & = & \epsilon \qquad \otherwise \\
   &&\\
   \writeact(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)   & = & \epsilon \\
   \writeact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast) & = & {\byte_2}^\ast \\
   \writeact(\act)  & = & \epsilon \qquad \otherwise \\
   &&\\
   \offsetact(\act)   & = & \u32  \qquad \iff \locaux(\act) = \reg[\u32] \ \\
   \\
   \syncact \ldots     & = & \ldots \\
   \rangeact \ldots    & = & \ldots \\
   \\
   \tearfreeact \ldots & = & \ldots \\
   \\
   \X{func}_{\reg}(\act_1^\ast~\act~\act_2^\ast~\AT~\time) & = & \X{func}(\act) \qquad \iff \locaux(\act) = \reg[\u32]  \\
   \X{func}_{\reg}(\act_1^\ast~\act~\act_2^\ast~\AT~\time, \act_3^\ast~\act'~\act_4^\ast~\AT~\time') & = & \X{func}(\act.\act') \qquad \iff \locaux(\act) = \locaux(\act') = \reg[\u32]  \\
   \end{array}

.. todo:: Add more auxiliary functions

.. todo:: add prose intuition

.. math::
   \frac{
     \forall \reg, \, \vdash_{\reg} \trace \consistentwith
   }{
     \vdash \trace \consistent
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{}}
       \forall \evt_R \in \readingact_{\reg}(\trace), \exists \evt_W^\ast,
         \trace \vdash_{\reg} \evt_R \readseachfrom \evt_W^\ast \\
       \forall \evt_I, \evt \in \trace, \,
         \ordact_{\reg}(\evt_I) = \INIT \wedge
         \evt_I \neq \evt \wedge
         \overlapact(\evt_I, \evt) \Rightarrow \evt_I \prechb \evt
     \end{array}
   }{
     \vdash_{\reg} \trace \consistentwith
   }

.. math::
   \frac{
     \begin{array}[b]{@{}c@{}}
       \left|\evt_W^\ast\right| = |\readact_{\reg}(\evt_R)| \\
       \forall i < |\evt_W^\ast|,
         \trace \vdash_{\reg}^i \evt_R \readsfrom \left(\evt_W^\ast[i]\right)
       \\
       \vdash_{\reg} \evt_R \notear \evt_W^\ast
     \end{array}
   }{
     \trace \vdash_{\reg} \evt_R \readseachfrom \evt_W^\ast
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{}}
       \evt_R \neq \evt_W \\
       \evt_W \in \writingact_{\reg}(\trace)
     \end{array}
     \qquad
     \begin{array}[b]{@{}r@{}}
       \trace \vdash_{\reg}^{i,k} \evt_R \valueconsistent \evt_W \\
       \trace \vdash_{\reg}^k \evt_R \hbconsistent \evt_W
     \end{array}
     \qquad
     \trace \vdash_{\reg} \evt_R \sclastvisible \evt^\ast_W
   }{
     \trace \vdash_{\reg}^i \evt_R \readsfrom \evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{@{}r@{~}c@{~}l@{}}
       \readact_{\reg}(\evt_R)[i] &=& \writeact_{\reg}(\evt_W)[j] \\
       k = \offsetact_{\reg}(\evt_R) + i &=& \offsetact_{\reg}(\evt_W) + j
     \end{array}
  }{
     \trace \vdash_{\reg}^{i,k} \evt_R \valueconsistent \evt_W
  }

.. math::
   \frac{
     \begin{array}[b]{@{}c}
       \neg (\evt_R \prechb \evt_W) \\
       \syncact_{\reg}(\evt_W, \evt_R) \Rightarrow \evt_W \prechb \evt_R
     \end{array}
    \qquad
    \begin{array}[b]{@{}l@{}}
      \forall \evt'_W \in \writingact_{\reg}(\trace),\\
      \quad \evt_W \prechb \evt'_W \prechb \evt_R \Rightarrow k \notin \rangeact_{\reg}(\evt'_W)
    \end{array}
   }{
    \trace \vdash_{\reg}^k \evt_R \hbconsistent \evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{@{}l@{\qquad}l@{}}
       \forall \evt'_W \in \writingact_{\reg}(\trace), \evt_W \prechb \evt_R \Rightarrow \\
       \quad \evt_W \prectot \evt'_W \prectot \evt_R \wedge \syncact_{\reg}(\evt_W, \evt_R) \Rightarrow \neg \syncact_{\reg}(\evt'_W, \evt_R) \\
       \quad \evt_W \prechb \evt'_W \prectot \evt_R  \Rightarrow \neg\syncact_{\reg}(\evt'_W, \evt_R) \\
       \quad \evt_W \prectot \evt'_W \prechb \evt_R \Rightarrow \neg\syncact_{\reg}(\evt_W, \evt'_W)
     \end{array}
   }{
     \trace \vdash_{\reg} \evt_R \sclastvisible \evt_W
   }

.. math::
   \frac{
     \tearfreeact_{\reg}(\evt_R) \Rightarrow |\{\evt_W \in \evt_W^\ast ~|~ \sameact_{\reg}(\evt_R, \evt_W) \wedge \tearfreeact_{\reg}(\evt_W)\}| \leq 1
   }{
     \vdash_{\reg} \evt_R \notear \evt_W^\ast
   }


.. [#cite-oopsla2019]
   The semantics of the relaxed memory model is derived from the following article:
   Conrad Watt, Andreas Rossberg, Jean Pichon-Pharabod. |OOPSLA2019|_. Proceedings of the ACM on Programming Languages (OOPSLA 2019). ACM 2019.
