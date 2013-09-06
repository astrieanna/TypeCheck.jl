## The Julia Programming Language

Julia is a high-performance, dynamically-typed, JIT-compiled language aimed at scientific computing.
Its excellent facillities for functional and meta-programming have lead some people to suggest that it is a Lisp with syntax.
The syntax is similar to Matlab or Ruby.
The similarity to Matlab is intentional:
it is a choice designed to ease the migration of code (and programmers).

Julia is designed to be fast, practical, and approachable.
There are no new ideas, just especially well-executed existing ones.
The aspect that is most likely to be new to programmers is multiple dispatch.
While Common Lisp and Dylan can do multiple dispatch,
Julia uses it as it's primary paradigm.
In Julia, named functions are generic functions;
they are polymorphic over different types, orders, and numbers of arguments
through having methods that each handle one signature.
An important aspect of Julia's performance is making multiple dispatch fast.
For my work, an advantage of multiple dispatch is that it incentivizes programmers to write type annotations on their function arguments.

Julia uses types in all the ways that don't lead to arguments with the programmer:
inference, optimizations, documentation, and dispatch.
The type inference code is written entirely in the language,
which is possible because if you lack type inference you can general slow, equivalent code that assumes everything is of type `Any`.

There are two kinds of types: concrete (leaf) types and abstract types.
Concrete types can be instantiated.
Abstract types can have subtypes.
Every type has exactly one super type.
Every type is decended from `Any`. (Except for `None`)
Concrete types (can?) have fields; you would call them structs or records in other languages.
They are memory-compatible with C-structs.
By default, concrete types are mutable, meaning that when you instantiate them, their fields' values are mutable.
By using the `immutable` keyword (rather than `type`), the user can define an immutable types, whose fields will all be immutable.
Because the compiler can guarantee that the fields are immutable,
it can take advantage of more optimizations, in addition to maintaining this condition that the programmer expects to hold.
