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

.. math::
   \begin{array}{rcl}
   \timeevt(\act^\ast~\AT~\time_p~\time)     & = & \time \\
   &&\\
   \locact(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \loc \\
   \locact(\AWR_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \loc \\
   \locact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)   & = & \loc \\
   &&\\
   \ordact(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \ord \\
   \ordact(\AWR_{\ord}~\loc~\byte^\ast~\NOTEARS^?)     & = & \ord \\
   \ordact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)   & = & \SEQCST \\
   &&\\
   \overlapact(\act_1, \act_2)  & = & (\rangeact(\act_1) \cup \rangeact(\act_2) \neq \epsilon)  \\
   \sameact(\act_1, \act_2) & = & (\rangeact(\act_1) = \rangeact(\act_2)) \\
   &&\\
   \readingact(\act)     & = & (\readact(\act) \neq \epsilon) \\
   \writingact(\act)     & = & (\writeact(\act) \neq \epsilon) \\
   &&\\
   \readact(\ARD_{\ord}~\loc~\byte^\ast~\NOTEARS^?)    & = & \byte^\ast \\
   \readact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast)  & = & {\byte_1}^\ast \\
   \readact(\act)  & = & \epsilon \qquad (\otherwise) \\
   &&\\
   \writeact(\AWR_{\ord}~\loc~\byte^\ast~\NOTEARS^?)   & = & \byte^\ast \\
   \writeact(\ARMW~\loc~{\byte_1}^\ast~{\byte_2}^\ast) & = & {\byte_2}^\ast \\
   \writeact(\act)  & = & \epsilon \qquad (\otherwise) \\
   &&\\
   \offsetact(\act)   & = & \u32  \qquad (\iff~\locact(\act) = \reg[\u32]) \\
   &&\\
   \syncact(\act_1,\act_2)     & = & (\sameact(\act_1,\act_2) \wedge \\
   && \qquad \ordact(\act_1) = \ordact(\act_2) = \SEQCST) \\
   \rangeact(\act)    & = & [\u32 \ldots \u32 + n - 1] \\
    &&  (\iff~\locact(\act) = \reg[\u32] \wedge \\
    && \quad n = \F{max}(|\readact(\act)|,|\writeact(\act)|)) \\
   &&\\
   \tearfreeact(\ARD_{\ord}~\loc~\byte^\ast)    & = & \bot \qquad (\iff~\ord = \UNORD \vee \ord = \INIT) \\
   \tearfreeact(\AWR_{\ord}~\loc~\byte^\ast)    & = & \bot \qquad (\iff~\ord = \UNORD \vee \ord = \INIT) \\
   \tearfreeact(\act)    & = & \top \qquad (\otherwise) \\
   &&\\
   \X{func}_{\reg}(\act_1^\ast~\act~\act_2^\ast~\AT~\time_p~\time) & = & \X{func}(\act) \\
     &&  (\iff~\locact(\act) = \reg[\u32])  \\
   \X{func}_{\reg}(\act_1^\ast~\act~\act_2^\ast~\AT~\time_p~\time,  \quad &&\\
   \qquad \act_3^\ast~\act'~\act_4^\ast~\AT~\time'_p~\time') & = & \X{func}(\act,\act') \\
     && (\iff~\locact(\act) = \locact(\act') = \reg[\u32])  \\
   \end{array}

.. todo:: add loc for wait/woken/timeout/notify

.. todo:: Double check notears

.. todo:: Tidy up range

.. todo:: add prose intuition?


.. _relaxed-trace:

Traces
~~~~~~

.. todo:: novel notation here?

A trace is a coinductive set of :ref:`events <syntax-evt>`. A trace is considered to be a *pre-execution* of a given :ref:`global configuration <syntax-config>` if it can be derived from the events emitted by the coinductive closure of the :ref:`global reduction relation <syntax-reduction>` on that configuration, and all the :ref:`time stamps <syntax-time>` of its constituent events are distinct.

.. math::
     \begin{array}{c}
       \config \stepto^{\evt} \config' \qquad \vdash \config' : \trace \qquad \timeevt(\evt) \notin \timeevt^\ast(\trace) \\[0.2ex]
       \hline \\[-0.8ex]
       \hline \\[-0.8ex]
       \vdash \config : \evt~\trace
     \end{array}

When a WebAssembly program is executed, all behaviours observed during that execution must correspond to a single :ref:`consistent <relaxed-consistent>` pre-execution of that execution's starting :ref:`configuration <syntax-config>`.


.. _relaxed-consistent:

Consistency
~~~~~~~~~~~

.. todo:: add prose intuition

.. math::
   \frac{
     \forall \reg,~ \vdash_{\reg} \trace~\consistentwith
   }{
     \vdash \trace~\consistent
   }

.. math::
   \frac{
     \begin{array}[b]{@{}c@{}}
       \vdash_{\reg} \trace~\suspensionsconsistentwith \\
       \forall \evt_R \in \readingact_{\reg}(\trace), \exists \evt_W^\ast,
         \trace \vdash_{\reg} \evt_R~\readseachfrom~\evt_W^\ast \\
       \forall \evt_I, \evt \in \trace, \,
         \ordact_{\reg}(\evt_I) = \INIT \wedge
         \evt_I \neq \evt \wedge
         \overlapact(\evt_I, \evt) \Rightarrow \evt_I \prechb \evt
     \end{array}
   }{
     \vdash_{\reg} \trace~\consistentwith
   }

.. math::
   \frac{
     \begin{array}[b]{@{}c@{}}
       \left|\evt_W^\ast\right| = |\readact_{\reg}(\evt_R)| \\
       \forall i < |\evt_W^\ast|,
         \trace \vdash_{\reg}^i \evt_R~\readsfrom~\left(\evt_W^\ast[i]\right)
       \\
       \vdash_{\reg} \evt_R~\notear~\evt_W^\ast
     \end{array}
   }{
     \trace \vdash_{\reg} \evt_R~\readseachfrom~\evt_W^\ast
   }

.. math::
   \frac{
     \begin{array}[b]{@{}c}
       \evt_R \neq \evt_W  \\
       \evt_W \in \writingact_{\reg}(\trace) \\
       \trace \vdash_{\reg}^{i,k} \evt_R~\valueconsistent~\evt_W \\
       \trace \vdash_{\reg}^k \evt_R~\hbconsistent~\evt_W \\
       \trace \vdash_{\reg} \evt_R~\sclastvisible~\evt^\ast_W
     \end{array}
   }{
     \trace \vdash_{\reg}^i \evt_R~\readsfrom~\evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{@{}r@{~}c@{~}l@{}}
       \readact_{\reg}(\evt_R)[i] &=& \writeact_{\reg}(\evt_W)[j] \\
       k = \offsetact_{\reg}(\evt_R) + i &=& \offsetact_{\reg}(\evt_W) + j
     \end{array}
  }{
     \trace \vdash_{\reg}^{i,k} \evt_R~\valueconsistent~\evt_W
  }

.. math::
   \frac{
     \begin{array}[b]{@{}c}
       \neg (\evt_R \prechb \evt_W) \\
       \syncact_{\reg}(\evt_W, \evt_R) \Rightarrow \evt_W \prechb \evt_R \\
       \forall \evt'_W \in \writingact_{\reg}(\trace), \evt_W \prechb \evt'_W \prechb \evt_R \Rightarrow k \notin \rangeact_{\reg}(\evt'_W)
    \end{array}
   }{
    \trace \vdash_{\reg}^k \evt_R~\hbconsistent~\evt_W
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
     \trace \vdash_{\reg} \evt_R~\sclastvisible~\evt_W
   }

.. math::
   \frac{
     \begin{array}[b]{l@{}}
       \tearfreeact_{\reg}(\evt_R) \Rightarrow \\
        \quad  |\{\evt_W \in \evt_W^\ast ~|~ \sameact_{\reg}(\evt_R, \evt_W) \wedge \tearfreeact_{\reg}(\evt_W)\}| \leq 1
     \end{array}
   }{
     \vdash_{\reg} \evt_R~\notear~\evt_W^\ast
   }

.. math::
   \frac{
     TODO
   }{
     \vdash_{\reg} \trace~\suspensionsconsistentwith
   }


.. todo:: pull out the trace events which denote wait/wake actions as a timestamped list, check queue behaviour


.. [#cite-oopsla2019]
   The semantics of the relaxed memory model is derived from the following article:
   Conrad Watt, Andreas Rossberg, Jean Pichon-Pharabod. |OOPSLA2019|_. Proceedings of the ACM on Programming Languages (OOPSLA 2019). ACM 2019.
