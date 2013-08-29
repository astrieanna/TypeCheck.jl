TypeCheck.jl
============

A (work-in-progress) TypeChecker for the Julia programming language.

Julia is a dynamically typed language, but some optional type-checking could come in handy.

The goal is to detect:

1. **Places where a normal typechecker would reject the program**
     (for example, when a no method error would probably occur)
2. **Unstable types**
     (places where the type of a variable changes over the course of a loop)

        require("TypeChecker.jl")
        check_all_module(Base;foo=check_loop_types)

3. **Functions whose return type depends on the values (rather than types) of its arguments**

        require("TypeChecker.jl")
        check_all_module(Base;foo=check_return_value)

