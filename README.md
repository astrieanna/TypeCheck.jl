TypeCheck.jl
============

A (work-in-progress) TypeChecker for the Julia programming language.

Julia is a dynamically typed language, but some optional type-checking could come in handy.

The goal is to detect:

1. **Places where a normal typechecker would reject the program**
     (for example, when a no method error would probably occur)
2. **Unstable types**
     (places where the type of a variable changes over the course of a loop)
3. **Functions whose return type depends on the values (rather than types) of its arguments**
     (this is all it can currently (try to) do)

