.. index:: ! runtime
.. _syntax-runtime:

Runtime Structure
-----------------

:ref:`Store <store>`, :ref:`stack <stack>`, and other *runtime structure* forming the WebAssembly abstract machine, such as :ref:`values <syntax-val>` or :ref:`module instances <syntax-moduleinst>`, are made precise in terms of additional auxiliary syntax.


.. index:: ! value, constant, value type, integer, floating-point
   pair: abstract syntax; value
.. _syntax-val:

Values
~~~~~~

WebAssembly computations manipulate *values* of the four basic :ref:`value types <syntax-valtype>`: :ref:`integers <syntax-int>` and :ref:`floating-point data <syntax-float>` of 32 or 64 bit width each, respectively.

In most places of the semantics, values of different types can occur.
In order to avoid ambiguities, values are therefore represented with an abstract syntax that makes their type explicit.
It is convenient to reuse the same notation as for the |CONST| :ref:`instructions <syntax-const>` producing them:

.. math::
   \begin{array}{llcl}
   \production{(value)} & \val &::=&
     \I32.\CONST~\i32 \\&&|&
     \I64.\CONST~\i64 \\&&|&
     \F32.\CONST~\f32 \\&&|&
     \F64.\CONST~\f64
   \end{array}


.. index:: ! result, value, trap
   pair: abstract syntax; result
.. _syntax-result:

Results
~~~~~~~

A *result* is the outcome of a computation.
It is either a sequence of :ref:`values <syntax-val>` or a :ref:`trap <syntax-trap>`.

.. math::
   \begin{array}{llcl}
   \production{(result)} & \result &::=&
     \val^\ast \\&&|&
     \TRAP
   \end{array}

.. note::
   In the current version of WebAssembly, a result can consist of at most one value.


.. index:: ! address, store, function instance, table instance, memory instance, global instance, embedder
   pair: abstract syntax; function address
   pair: abstract syntax; table address
   pair: abstract syntax; memory address
   pair: abstract syntax; global address
   pair: function; address
   pair: table; address
   pair: memory; address
   pair: global; address
.. _syntax-funcaddr:
.. _syntax-tableaddr:
.. _syntax-memaddr:
.. _syntax-globaladdr:
.. _syntax-addr:

Addresses
~~~~~~~~~

:ref:`Function instances <syntax-funcinst>`, :ref:`table instances <syntax-tableinst>`, :ref:`memory instances <syntax-meminst>`, and :ref:`global instances <syntax-globalinst>` in the :ref:`store <syntax-store>` are referenced with abstract *addresses*.
Each address uniquely determines a respective component in the store.
Other than that the form that addresses take is unspecified and cannot be observed.

.. math::
   \begin{array}{llll}
   \production{(address)} & \addr &::=&
     \dots \\
   \production{(function address)} & \funcaddr &::=&
     \addr \\
   \production{(table address)} & \tableaddr &::=&
     \addr \\
   \production{(memory address)} & \memaddr &::=&
     \addr \\
   \production{(global address)} & \globaladdr &::=&
     \addr \\
   \end{array}

An :ref:`embedder <embedder>` may assign identity to :ref:`exported <syntax-export>` store objects corresponding to their addresses,
even where this identity is not observable from within WebAssembly code itself
(such as for :ref:`function instances <syntax-funcinst>` or immutable :ref:`globals <syntax-globalinst>`).

.. note::
   Addresses are *dynamic*, globally unique references to runtime objects,
   in contrast to :ref:`indices <syntax-index>`,
   which are *static*, module-local references to their original definitions.
   A *memory address* |memaddr| denotes the abstract address *of* a memory *instance* in the store,
   not an offset *inside* a memory instance.



.. index:: ! time stamp, ! happens-before, thread, event
.. _syntax-time:
.. _relaxed-prechb:

Time Stamps
~~~~~~~~~~~

In order to track the relative ordering in the execution of multiple :ref:`threads <syntax-thread>` and the occurrence of :ref:`events <syntax-evt>`,
the semantics uses a notion of abstract *time stamps*.

.. math::
   \begin{array}{llll}
   \production{(time stamp)} & \time &::=&
     \dots \\
   \end{array}

Each time stamp denotes a discrete point in time, and is drawn from an infinite set.
The shape of time stamps is not specified or observable.
However, time stamps form a partially ordered set:
a time stamp :math:`\time_1` *happens before* :math:`\time_2`, written :math:`\time_1 \prechb \time_2`, if it is known to have occurred earlier in time.

.. note:

   Although the semantics choses time stamps non-deterministically,
   it includes conditions that enforce some ordering constraints on the chosen values, thereby imposing an ordering on execeution and events that guarantees well-defined causalities.

   The ordering is partial because some events have an unspecified relative order -- in particular, when they occur in separate threads without intervening synchronisation.

.. _relaxed-prectot:
.. todo:: define prectot here as well?


.. _notation-attime:

Conventions
...........

* The meta variable :math:`h` ranges over time stamps where clear from context.

* The notation :math:`(X~\AT~h)` is a shorthand for the :ref:`record <notation-record>` :math:`\{\ATVAL~X, \ATTIME~h\}` that annotates a semantic object :math:`X` with a time stamp :math:`h`.


.. index:: ! store, address, function instance, table instance, memory instance, global instance, module, allocation
   pair: abstract syntax; store
.. _store:

Store
~~~~~

A *store* represents state that can be manipulated by WebAssembly programs.
The overall state of the WebAssembly abstract machine can consist of multiple disjoint stores,
separated into per-:ref:`thread <syntax-thread>` *local stores* and a single *shared store*. [#cite-oopsla2019]_

.. _syntax-store:

Local Store
...........

A *local store* represents all state that can be manipulated by programs within a single :ref:`thread <syntax-thread>`.
It consists of the runtime representation of all *instances* of :ref:`functions <syntax-funcinst>`, :ref:`tables <syntax-tableinst>`, :ref:`memories <syntax-meminst>`, and :ref:`globals <syntax-globalinst>` that have been :ref:`allocated <alloc>` during the life time of that thread. [#gc]_

Syntactically, a local store is defined as a :ref:`map <notation-map>` from known :ref:`addresses <syntax-addr>` to the allocated instances of each category:

.. math::
   \begin{array}{llll}
   \production{(store)} & \store &::=&
     (\addr \mapsto \inst)^\ast \\
   \production{(instance)} & \inst &::=&
     \funcinst ~|~
     \tableinst ~|~
     \meminst ~|~
     \globalinst \\
   \end{array}

It is an invariant of the semantics that none of the memory instances :math:`\meminst` in a local store is :ref:`shared <syntax-shared>`.

.. [#gc]
   In practice, implementations may apply techniques like garbage collection to remove objects from the store that are no longer referenced.
   However, such techniques are not semantically observable,
   and hence outside the scope of this specification.


.. index:: ! shared store, memory instance, module, allocation
   pair: abstract syntax; shared store
.. _syntax-sharedstore:
.. _sharedstore:

Shared Store
............

The *shared store* represents all global state that can be shared between multiple :ref:`threads <syntax-thread>`.
It consists of the runtime representation of all *instances* of :ref:`shared <syntax-shared>` :ref:`memories <syntax-meminst>` that have been :ref:`allocated <alloc>` by any thread during the life time of the abstract machine.

Syntactically, the shared store is defined as a :ref:`map <notation-map>` from known :ref:`addresses <syntax-addr>` to instances :ref:`annotated <notation-attime>` with the :ref:`time <syntax-time>` of their creation.

.. math::
   \begin{array}{llll}
   \production{(shared store)} & \sharedstore &::=&
     (\memaddr \mapsto \meminst \AT \time)^\ast, \\
   \end{array}

It is an invariant of the semantics that all memory instances :math:`\meminst` in a shared store are :math:`shared <syntax-shared>`.

.. note::
   In future versions of WebAssembly, other entities than just memories may be sharable and contained in a shared store.

Conventions
...........

* The meta variable :math:`S` ranges over local stores where clear from context.

* The meta variable :math:`\X{SS}` ranges over shared stores where clear from context.


.. index:: ! instance, function type, function instance, table instance, memory instance, global instance, export instance, table address, memory address, global address, index, name
   pair: abstract syntax; module instance
   pair: module; instance
.. _syntax-moduleinst:

Module Instances
~~~~~~~~~~~~~~~~

A *module instance* is the runtime representation of a :ref:`module <syntax-module>`.
It is created by :ref:`instantiating <exec-instantiation>` a module,
and collects runtime representations of all entities that are imported, defined, or exported by the module.

.. math::
   \begin{array}{llll}
   \production{(module instance)} & \moduleinst &::=& \{
     \begin{array}[t]{l@{~}ll}
     \MITYPES & \functype^\ast, \\
     \MIFUNCS & \funcaddr^\ast, \\
     \MITABLES & \tableaddr^\ast, \\
     \MIMEMS & \memaddr^\ast, \\
     \MIGLOBALS & \globaladdr^\ast, \\
     \MIEXPORTS & \exportinst^\ast ~\} \\
     \end{array}
   \end{array}

Each component references runtime instances corresponding to respective declarations from the original module -- whether imported or defined -- in the order of their static :ref:`indices <syntax-index>`.
:ref:`Function instances <syntax-funcinst>`, :ref:`table instances <syntax-tableinst>`, :ref:`memory instances <syntax-meminst>`, and :ref:`global instances <syntax-globalinst>` are referenced with an indirection through their respective :ref:`addresses <syntax-addr>` in the :ref:`store <syntax-store>`.

It is an invariant of the semantics that all :ref:`export instances <syntax-exportinst>` in a given module instance have different :ref:`names <syntax-name>`.


.. index:: ! function instance, module instance, function, closure, module, ! host function, invocation
   pair: abstract syntax; function instance
   pair: function; instance
.. _syntax-hostfunc:
.. _syntax-funcinst:

Function Instances
~~~~~~~~~~~~~~~~~~

A *function instance* is the runtime representation of a :ref:`function <syntax-func>`.
It effectively is a *closure* of the original function over the runtime :ref:`module instance <syntax-moduleinst>` of its originating :ref:`module <syntax-module>`.
The module instance is used to resolve references to other definitions during execution of the function.

.. math::
   \begin{array}{llll}
   \production{(function instance)} & \funcinst &::=&
     \{ \FITYPE~\functype, \FIMODULE~\moduleinst, \FICODE~\func \} \\ &&|&
     \{ \FITYPE~\functype, \FIHOSTCODE~\hostfunc \} \\
   \production{(host function)} & \hostfunc &::=& \dots \\
   \end{array}

.. todo:: need to represent host functions differently to encompass threading

A *host function* is a function expressed outside WebAssembly but passed to a :ref:`module <syntax-module>` as an :ref:`import <syntax-import>`.
The definition and behavior of host functions are outside the scope of this specification.
For the purpose of this specification, it is assumed that when :ref:`invoked <exec-invoke-host>`,
a host function behaves non-deterministically,
but within certain :ref:`constraints <exec-invoke-host>` that ensure the integrity of the runtime.

.. note::
   Function instances are immutable, and their identity is not observable by WebAssembly code.
   However, the :ref:`embedder <embedder>` might provide implicit or explicit means for distinguishing their :ref:`addresses <syntax-funcaddr>`.


.. index:: ! table instance, table, function address, table type, embedder, element segment
   pair: abstract syntax; table instance
   pair: table; instance
.. _syntax-funcelem:
.. _syntax-tableinst:

Table Instances
~~~~~~~~~~~~~~~

A *table instance* is the runtime representation of a :ref:`table <syntax-table>`.
It holds a vector of *function elements* and an optional maximum size, if one was specified in the :ref:`table type <syntax-tabletype>` at the table's definition site.

Each function element is either empty, representing an uninitialized table entry, or a :ref:`function address <syntax-funcaddr>`.
Function elements can be mutated through the execution of an :ref:`element segment <syntax-elem>` or by external means provided by the :ref:`embedder <embedder>`.

.. math::
   \begin{array}{llll}
   \production{(table instance)} & \tableinst &::=&
     \{ \TIELEM~\vec(\funcelem), \TIMAX~\u32^? \} \\
   \production{(function element)} & \funcelem &::=&
     \funcaddr^? \\
   \end{array}

It is an invariant of the semantics that the length of the element vector never exceeds the maximum size, if present.

.. note::
   Other table elements may be added in future versions of WebAssembly.


.. index:: ! memory instance, memory, byte, ! page size, memory type, embedder, data segment, instruction
   pair: abstract syntax; memory instance
   pair: memory; instance
.. _page-size:
.. _syntax-meminst:

Memory Instances
~~~~~~~~~~~~~~~~

.. todo:: We used to update the memory type when a memory is grown. This does not work for shared memories. In fact, the "current" type of a shared memory is nondeterministic. We need to model that during instantiation somehow.

A *memory instance* is the runtime representation of a linear :ref:`memory <syntax-mem>`.
It records its original :ref:`memory type <syntax-memtype>`
and takes one of two different shapes depending on whether that type is :ref:`shared <syntax-shared>` or not.
It is an invariant of the semantics that the shape always matches the type.

.. math::
   \begin{array}{llll}
   \production{(memory instance)} & \meminst &::=&
     \{ \MITYPE~\memtype, \MIDATA~\vec(\byte) \} \\ &&|&
     \{ \MITYPE~\memtype \} \\
   \end{array}

The instance of a memory with :ref:`unshared <syntax-unshared>` :ref:`type <syntax-memtype>` holds a vector of :ref:`bytes <syntax-byte>` directly representing its state.
The length of the vector always is a multiple of the WebAssembly *page size*, which is defined to be the constant :math:`65536` -- abbreviated :math:`64\,\F{Ki}`.
The bytes can be mutated through :ref:`memory instructions <syntax-instr-memory>`, the execution of an active :ref:`data segment <syntax-data>`, or by external means provided by the :ref:`embedder <embedder>`.
It is an invariant of the semantics that the length of the byte vector, divided by page size, never exceeds the maximum size of :math:`\memtype`, if present.

For memories of :ref:`shared <syntax-shared>` :ref:`type <syntax-memtype>`, no state is recorded in the instance itself.
Instead of representing the contents of a memory directly the abstract machine hence separately records :ref:`traces <relaxed-trace>` of corresponding memory :ref:`events <syntax-evt>` that describe all accesses that occur.


.. index:: ! global instance, global, value, mutability, instruction, embedder
   pair: abstract syntax; global instance
   pair: global; instance
.. _syntax-globalinst:

Global Instances
~~~~~~~~~~~~~~~~

A *global instance* is the runtime representation of a :ref:`global <syntax-global>` variable.
It holds an individual :ref:`value <syntax-val>` and a flag indicating whether it is mutable.

.. math::
   \begin{array}{llll}
   \production{(global instance)} & \globalinst &::=&
     \{ \GIVALUE~\val, \GIMUT~\mut \} \\
   \end{array}

The value of mutable globals can be mutated through :ref:`variable instructions <syntax-instr-variable>` or by external means provided by the :ref:`embedder <embedder>`.


.. index:: ! export instance, export, name, external value
   pair: abstract syntax; export instance
   pair: export; instance
.. _syntax-exportinst:

Export Instances
~~~~~~~~~~~~~~~~

An *export instance* is the runtime representation of an :ref:`export <syntax-export>`.
It defines the export's :ref:`name <syntax-name>` and the associated :ref:`external value <syntax-externval>`.

.. math::
   \begin{array}{llll}
   \production{(export instance)} & \exportinst &::=&
     \{ \EINAME~\name, \EIVALUE~\externval \} \\
   \end{array}


.. index:: ! external instance, function instance, table instance, memory instance, global instance, function, table, memory, global
   pair: abstract syntax; external instance
   pair: external; instance
.. _syntax-externinst:

External Instances
~~~~~~~~~~~~~~~~~~

An *external instance* is an instance that can be imported or exported,
i.e., either a :ref:`function instance <syntax-funcinst>`, :ref:`table instance <syntax-tableinst>`, :ref:`memory instance <syntax-meminst>`, or :ref:`global instances <syntax-globalinst>`.

.. math::
   \begin{array}{llcl}
   \production{(external instance)} & \externinst &::=&
     \funcinst ~|~
     \tableinst ~|~
     \meminst ~|~
     \globalinst \\
   \end{array}



.. index:: ! external value, function address, table address, memory address, global address, store, function, table, memory, global
   pair: abstract syntax; external value
   pair: external; value
.. _syntax-externval:

External Values
~~~~~~~~~~~~~~~

An *external value* is the address of an :ref:`external instance <syntax-externinst>`.
Consequently, it is either a :ref:`function address <syntax-funcaddr>`, :ref:`table address <syntax-tableaddr>`, :ref:`memory address <syntax-memaddr>`, or :ref:`global address <syntax-globaladdr>`, denoting a respecive instance in the shared :ref:`store <syntax-store>`.

.. math::
   \begin{array}{llcl}
   \production{(external value)} & \externval &::=&
     \EVFUNC~\funcaddr \\&&|&
     \EVTABLE~\tableaddr \\&&|&
     \EVMEM~\memaddr \\&&|&
     \EVGLOBAL~\globaladdr \\
   \end{array}


Conventions
...........

The following auxiliary notation is defined for sequences of external values.
It filters out entries of a specific kind in an order-preserving fashion:

* :math:`\evfuncs(\externval^\ast) = [\funcaddr ~|~ (\EVFUNC~\funcaddr) \in \externval^\ast]`

* :math:`\evtables(\externval^\ast) = [\tableaddr ~|~ (\EVTABLE~\tableaddr) \in \externval^\ast]`

* :math:`\evmems(\externval^\ast) = [\memaddr ~|~ (\EVMEM~\memaddr) \in \externval^\ast]`

* :math:`\evglobals(\externval^\ast) = [\globaladdr ~|~ (\EVGLOBAL~\globaladdr) \in \externval^\ast]`


.. index:: ! stack, ! frame, ! label, instruction, store, activation, function, call, local, module instance
   pair: abstract syntax; frame
   pair: abstract syntax; label
.. _syntax-frame:
.. _syntax-label:
.. _frame:
.. _label:
.. _stack:

Stack
~~~~~

Besides the :ref:`store <store>`, most :ref:`instructions <syntax-instr>` interact with an implicit *stack*.
The stack contains three kinds of entries:

* *Values*: the *operands* of instructions.

* *Labels*: active :ref:`structured control instructions <syntax-instr-control>` that can be targeted by branches.

* *Activations*: the *call frames* of active :ref:`function <syntax-func>` calls.

These entries can occur on the stack in any order during the execution of a program.
Stack entries are described by abstract syntax as follows.

.. note::
   It is possible to model the WebAssembly semantics using separate stacks for operands, control constructs, and calls.
   However, because the stacks are interdependent, additional book keeping about associated stack heights would be required.
   For the purpose of this specification, an interleaved representation is simpler.

Values
......

Values are represented by :ref:`themselves <syntax-val>`.

Labels
......

Labels carry an argument arity :math:`n` and their associated branch *target*, which is expressed syntactically as an :ref:`instruction <syntax-instr>` sequence:

.. math::
   \begin{array}{llll}
   \production{(label)} & \label &::=&
     \LABEL_n\{\instr^\ast\} \\
   \end{array}

Intuitively, :math:`\instr^\ast` is the *continuation* to execute when the branch is taken, in place of the original control construct.

.. note::
   For example, a loop label has the form

   .. math::
      \LABEL_n\{\LOOP~\dots~\END\}

   When performing a branch to this label, this executes the loop, effectively restarting it from the beginning.
   Conversely, a simple block label has the form

   .. math::
      \LABEL_n\{\epsilon\}

   When branching, the empty continuation ends the targeted block, such that execution can proceed with consecutive instructions.

Activations and Frames
......................

Activation frames carry the return arity :math:`n` of the respective function,
hold the values of its :ref:`locals <syntax-local>` (including arguments) in the order corresponding to their static :ref:`local indices <syntax-localidx>`,
and a reference to the function's own :ref:`module instance <syntax-moduleinst>`:

.. math::
   \begin{array}{llll}
   \production{(activation)} & \X{activation} &::=&
     \FRAME_n\{\frame\} \\
   \production{(frame)} & \frame &::=&
     \{ \ALOCALS~\val^\ast, \AMODULE~\moduleinst \} \\
   \end{array}

The values of the locals are mutated by respective :ref:`variable instructions <syntax-instr-variable>`.


.. _exec-expand:

Conventions
...........

* The meta variable :math:`L` ranges over labels where clear from context.

* The meta variable :math:`F` ranges over frames where clear from context.

* The following auxiliary definition takes a :ref:`block type <syntax-blocktype>` and looks up the :ref:`function type <syntax-functype>` that it denotes in the current frame:

.. math::
   \begin{array}{lll}
   \expand_F(\typeidx) &=& F.\AMODULE.\MITYPES[\typeidx] \\
   \expand_F([\valtype^?]) &=& [] \to [\valtype^?] \\
   \end{array}


.. index:: ! administrative instructions, function, function instance, function address, label, frame, instruction, trap, call, memory, memory instance, table, table instance, element, data, segment
   pair:: abstract syntax; administrative instruction
.. _syntax-trap:
.. _syntax-invoke:
.. _syntax-init_elem:
.. _syntax-init_data:
.. _syntax-suspend:
.. _syntax-instr-admin:

Administrative Instructions
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. note::
   This section is only relevant for the :ref:`formal notation <exec-notation>`.

In order to express the reduction of :ref:`traps <trap>`, :ref:`calls <syntax-call>`, and :ref:`control instructions <syntax-instr-control>`, the syntax of instructions is extended to include the following *administrative instructions*:

.. math::
   \begin{array}{llcl}
   \production{(administrative instruction)} & \instr &::=&
     \dots \\ &&|&
     \TRAP \\ &&|&
     \INVOKE~\funcaddr \\ &&|&
     \INITELEM~\tableaddr~\u32~\funcidx^\ast \\ &&|&
     \INITDATA~\memaddr~\u32~\byte^\ast \\ &&|&
     \LABEL_n\{\instr^\ast\}~\instr^\ast~\END \\ &&|&
     \FRAME_n\{\frame\}~\instr^\ast~\END \\ &&|&
     \WAITX~\loc~n \\ &&|&
     \NOTIFYX~\loc~n~m \\
   \end{array}

The |TRAP| instruction represents the occurrence of a trap.
Traps are bubbled up through nested instruction sequences, ultimately reducing the entire program to a single |TRAP| instruction, signalling abrupt termination.

The |INVOKE| instruction represents the imminent invocation of a :ref:`function instance <syntax-funcinst>`, identified by its :ref:`address <syntax-funcaddr>`.
It unifies the handling of different forms of calls.

The |INITELEM| and |INITDATA| instructions perform initialization of :ref:`element <syntax-elem>` and :ref:`data <syntax-data>` segments during module :ref:`instantiation <exec-instantiation>`.

.. note::
   The reason for splitting instantiation into individual reduction steps is to provide a semantics that is compatible with future extensions like threads.

The |LABEL| and |FRAME| instructions model :ref:`labels <syntax-label>` and :ref:`frames <syntax-frame>` :ref:`"on the stack" <exec-notation>`.
Moreover, the administrative syntax maintains the nesting structure of the original :ref:`structured control instruction <syntax-instr-control>` or :ref:`function body <syntax-func>` and their :ref:`instruction sequences <syntax-instr-seq>` with an |END| marker.
That way, the end of the inner instruction sequence is known when part of an outer sequence.

.. todo:: describe |WAITX| and |NOTIFYX|

.. todo:: add allocation instructions

.. todo:: add host instruction

.. note::
   For example, the :ref:`reduction rule <exec-block>` for |BLOCK| is:

   .. math::
      \BLOCK~[t^n]~\instr^\ast~\END \quad\stepto\quad
      \LABEL_n\{\epsilon\}~\instr^\ast~\END

   This replaces the block with a label instruction,
   which can be interpreted as "pushing" the label on the stack.
   When |END| is reached, i.e., the inner instruction sequence has been reduced to the empty sequence -- or rather, a sequence of :math:`n` |CONST| instructions representing the resulting values -- then the |LABEL| instruction is eliminated courtesy of its own :ref:`reduction rule <exec-label>`:

   .. math::
      \LABEL_m\{\instr^\ast\}~\val^n~\END \quad\stepto\quad \val^n

   This can be interpreted as removing the label from the stack and only leaving the locally accumulated operand values.

.. commented out
   Both rules can be seen in concert in the following example:

   .. math::
      \begin{array}{@{}ll}
      & (\F32.\CONST~1)~\BLOCK~[]~(\F32.\CONST~2)~\F32.\NEG~\END~\F32.\ADD \\
      \stepto & (\F32.\CONST~1)~\LABEL_0\{\}~(\F32.\CONST~2)~\F32.\NEG~\END~\F32.\ADD \\
      \stepto & (\F32.\CONST~1)~\LABEL_0\{\}~(\F32.\CONST~{-}2)~\END~\F32.\ADD \\
      \stepto & (\F32.\CONST~1)~(\F32.\CONST~{-}2)~\F32.\ADD \\
      \stepto & (\F32.\CONST~{-}1) \\
      \end{array}


.. index:: ! block context, instruction, branch
.. _syntax-ctxt-block:

Block Contexts
..............

In order to specify the reduction of :ref:`branches <syntax-instr-control>`, the following syntax of *block contexts* is defined, indexed by the count :math:`k` of labels surrounding a *hole* :math:`[\_]` that marks the place where the next step of computation is taking place:

.. math::
   \begin{array}{llll}
   \production{(block contexts)} & \XB^0 &::=&
     \val^\ast~[\_]~\instr^\ast \\
   \production{(block contexts)} & \XB^{k+1} &::=&
     \val^\ast~\LABEL_n\{\instr^\ast\}~\XB^k~\END~\instr^\ast \\
   \end{array}

This definition allows to index active labels surrounding a :ref:`branch <syntax-br>` or :ref:`return <syntax-return>` instruction.

.. note::
   For example, the :ref:`reduction <exec-br>` of a simple branch can be defined as follows:

   .. math::
      \LABEL_0\{\instr^\ast\}~\XB^l[\BR~l]~\END \quad\stepto\quad \instr^\ast

   Here, the hole :math:`[\_]` of the context is instantiated with a branch instruction.
   When a branch occurs,
   this rule replaces the targeted label and associated instruction sequence with the label's continuation.
   The selected label is identified through the :ref:`label index <syntax-labelidx>` :math:`l`, which corresponds to the number of surrounding |LABEL| instructions that must be hopped over -- which is exactly the count encoded in the index of a block context.


.. index:: ! event, ! action, time stamp, external instance, address, store, memory, table, value, byte
.. _syntax-evt:
.. _syntax-act:
.. _syntax-ord:
.. _syntax-loc:
.. _syntax-fld:
.. _syntax-storeval:

Events
~~~~~~

The interaction of a computation with the :ref:`shared store <syntax-sharedstore>` is described through *events*.
An event is a (possibly empty) set of *actions*, such as reads and writes,
that are atomically performed by the execution of an individual :ref:`instruction <syntax-instr>`.
Each event is annotated with a :ref:`time stamp <syntax-time>` that uniquely identifies it.

.. math::
   \begin{array}{llcl}
   \production{(event)} & \evt &::=&
     \act^\ast~\AT~\time \\
   \production{(action)} & \act &::=&
     \ARD_{\ord}~\loc~\storeval \\&&|&
     \AWR_{\ord}~\loc~\storeval \\&&|&
     \ARMW~\loc~\storeval~\storeval \\&&|&
     \hostact \\
   \production{(ordering)} & \ord &::=&
     \UNORD ~|~
     \SEQCST \\
   \production{(location)} & \loc &::=&
     \addr.\fld \\
   \production{(field)} & \fld &::=&
     \LLEN ~|~
     \LDATA[\u32] \\
   \production{(store value)} & \storeval &::=&
     \val ~|~
     b^\ast \\
   \end{array}

The access of *mutable* shared state is performed through the |ARD|, |AWR|, and |ARMW| actions.
They each access an :ref:`external instance <syntax-externinst>` at an abstract *location*.
Such a location consists of an :ref:`address <syntax-addr>` of a :ref:`shared <syntax-shared>` :ref:`memory <syntax-meminst>` instance and a symbolic *field* name in the respective object.
This is either |LLEN| for the size or |LDATA| for the vector of bytes.

In each case, read and write actions record the *store value* that has been read or written, which is either a regular :ref:`value <syntax-val>` or a sequence of :ref:`bytes <syntax-byte>`, depending on the location accessed.
An |ARMW| event, performing an atomic read-modify-write access, records both the store values read (first) and written (second);
it is an invariant of the semantics that both are either regular values of the same type or byte sequences of the same length.

|ARD| and |AWR| events are further annotated by a memory *ordering*, which describes whether the access is *unordered*, as e.g. performed by a regular :ref:`load or store instruction <syntax-instr-memory>`, or *sequentially consistent*, as e.g. performed by :ref:`atomic memory instructions <syntax-instr-atomic-memory>`.
A |ARMW| action always is sequentially consistent.

.. note::
   Future versions of WebAssembly may introduce additional orderings.

Finally, a *host action* is an action performed outside of WebAssembly code.
Its form and meaning is outside the scope of this specification.

.. note::
   An :ref:`embedder <embedder>` may define a custom set of host actions and respective ordering constraints to model other forms of interactions that are not expressible within WebAssembly, but whose ordering relative to WebAssembly events is relevant for the combined semantics.


Convention
..........

* The actions :math:`\ARD_{\ord}` and :math:`\AWR_{\ord}` are abbreviated to just :math:`\ARD` and :math:`\AWR` when :math:`\ord` is :math:`\UNORD`.

.. todo:: define notational shorthands over actions and events (or better put that in relaxed.rst?)


.. index:: ! configuration, ! thread, store, shared store, time stamp, instruction, function, frame, ! termination
.. _syntax-thread:
.. _syntax-config:

Configurations
~~~~~~~~~~~~~~

A *global configuration* describes the overall state of the abstract machine.
It consists of the current :ref:`shared store <syntax-sharedstore>` and a set of executing *threads*.

A thread consists of a local :ref:`store <syntax-store>` and a computation over a sequence of remaining :ref:`instructions <syntax-instr>`, :ref:`annotated <notation-attime>` with the :ref:`time <syntax-time>` it was last active.

A *local configuration* describes the state of an active function.
It consists of the local :ref:`store <syntax-store>` of the respective thread, the :ref:`frame <syntax-frame>` of the function, and the sequence of remaining :ref:`instructions <syntax-instr>` in that function.

.. math::
   \begin{array}{llcl}
   \production{(global configuration)} & \config &::=&
     \sharedstore; \thread^\ast \\
   \production{(thread)} & \thread &::=&
     \store; \instr^\ast~\AT~\time \\
   \production{(local configuration)} & \lconfig &::=&
     \store; \frame; \instr^\ast \\
   \end{array}

A thread has *terminated* when its instruction sequence has been reduced to a :ref:`result <syntax-result>`,
that is, either a sequence of :ref:`values <syntax-val>` or to a |TRAP|.


Convention
..........

* The meta variable :math:`P` ranges over threads where clear from context.


.. index:: ! reduction, configuration, ! termination

Reduction
~~~~~~~~~

Formally, WebAssembly computation is defined by two *small-step reduction* relations on global and local :ref:`configurations <syntax-config>`
that define how a single step of execution modifies these configurations, respectively.


Global Reduction
................

*Global reduction* is concerned with allocation in the global store and synchronization between multiple :ref:`threads <syntax-thread>`.
It emits a (possibly empty) set of events that are produced by the corresponding step of computation.

Formally, global reduction is a relation

.. math::
   \config \stepto^{\evt^\ast} \config

defined by inductive rewrite rules on global configurations.

The following structural rule for global reduction delegates to local reduction for single thread execution:

.. math::
   \begin{array}{@{}c@{}}
   \X{SS}; P_1^\ast~(S; \instr^\ast \AT h)~P_2^\ast
     \qquad \stepto^{\act^\ast \AT h'} \qquad
     \X{SS}; P_1^\ast~(S'; {\instr'}^\ast \AT h')~P_2^\ast \\
     \qquad (
       \begin{array}[t]{@{}r@{~}l@{}}
       \iff & S; F_\epsilon; \instr^\ast \stepto^{\act^\ast} S'; F'; {\instr'}^\ast) \\
       \wedge & h \prechb h' \\
       \wedge & (\X{SS}(\addr(\act)).\ATTIME \prechb h')^\ast \\
       \wedge & F_\epsilon = \{\AMODULE~\{\}\}) \\
       \end{array}
   \end{array}

.. note::
   The :ref:`time stamp <syntax-time>` :math:`h'` indicates the point in time at which the computation step takes place,
   marking both the emitted atomic event and the updated time of the thread.
   This time stamp is chosen non-deterministically in the rule.
   However, the second side condition ensures that the time :math:`h` of the last activity of the thread *happened before* :math:`h'`, thereby imposing *program order* for any events originating from the same thread.
   Similarly, the third side condition ensures that the allocation of any object accessed *happened before* :math:`h'`, ensuring causality and preventing use before definition.

   The empty :ref:`frame <syntax-frame>` :math:`F_\epsilon` is a dummy for initiating the reduction globally.
   It is an invariant of the semantics that it will never be accessed,
   because no local definitions are defined outside a function.


Local Reduction
...............

*Local reduction* defines the execution of individual :ref:`instructions <syntax-instr>`.
Each execution step can perform a (possibly empty) set of :ref:`actions <syntax-act>`.

Formally, this is described by a labelled relation

.. math::
   \lconfig \stepto^{\act^\ast} \lconfig

To avoid unnecessary clutter, the following conventions are employed in the notation for local reduction rules:

* The configuration's store :math:`S` is omitted from rules that do not touch it.

* The configuration's frame :math:`F` is omitted from rules that do not touch it.


.. index:: ! evaluation context, instruction, trap, label, frame, value
.. _syntax-ctxt-eval:

Evaluation Contexts
...................

The following definition of *evaluation context* and associated structural rules enable reduction inside instruction sequences and administrative forms as well as the propagation of traps:

.. math::
   \begin{array}{llll}
   \production{(evaluation contexts)} & E &::=&
     [\_] ~|~
     \val^\ast~E~\instr^\ast ~|~
     \LABEL_n\{\instr^\ast\}~E~\END \\
   \end{array}

.. math::
   \begin{array}{rcl}
   S; F; E[\instr^\ast] &\stepto& S'; F'; E[{\instr'}^\ast] \\
     && (\iff S; F; \instr^\ast \stepto S'; F'; {\instr'}^\ast) \\
   S; F; \FRAME_n\{F'\}~\instr^\ast~\END &\stepto& S'; F; \FRAME_n\{F''\}~\instr'^\ast~\END \\
     && (\iff S; F'; \instr^\ast \stepto S'; F''; {\instr'}^\ast) \\[1ex]
   S; F; E[\TRAP] &\stepto& S; F; \TRAP
     \qquad (\iff E \neq [\_]) \\
   S; F; \FRAME_n\{F'\}~\TRAP~\END &\stepto& S; F; \TRAP \\
   \end{array}

.. note::
   The restriction on evaluation contexts rules out contexts like :math:`[\_]` and :math:`\epsilon~[\_]~\epsilon` for which :math:`E[\TRAP] = \TRAP`.

   For an example of reduction under evaluation contexts, consider the following instruction sequence.

   .. math::
       (\F64.\CONST~x_1)~(\F64.\CONST~x_2)~\F64.\NEG~(\F64.\CONST~x_3)~\F64.\ADD~\F64.\MUL

   This can be decomposed into :math:`E[(\F64.\CONST~x_2)~\F64.\NEG]` where

   .. math::
      E = (\F64.\CONST~x_1)~[\_]~(\F64.\CONST~x_3)~\F64.\ADD~\F64.\MUL

   Moreover, this is the *only* possible choice of evaluation context where the contents of the hole matches the left-hand side of a reduction rule.


.. index:: ! host reduction, host

Host Reduction
..............

.. todo:: define


.. [#cite-oopsla2019]
   The semantics of shared stores is derived from the following article:
   Conrad Watt, Andreas Rossberg, Jean Pichon-Pharabod. |OOPSLA2019|_. Proceedings of the ACM on Programming Languages (OOPSLA 2019). ACM 2019.
