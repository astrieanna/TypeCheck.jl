TypeCheck.jl
============

A (work-in-progress) TypeChecker for the Julia programming language.

Julia is a dynamically typed language, but some optional type-checking could come in handy.

The goal is to detect:

1. **Places where a normal typechecker would reject the program**
     (for example, when a no method error would probably occur)
     Not yet implemented.

2. **Unstable types**
     (places where the type of a variable changes over the course of a loop)

        require("TypeChecker.jl")
        check_all_module(Base;foo=check_loop_types)

3. **Functions whose return type depends on the values (rather than types) of its arguments**

        require("TypeChecker.jl")
        check_all_module(Base;foo=check_return_value)

## API

    check_all_module(m::Module;foo=check_return_value)

The function `check_all_module` takes a Module as its only positional argument.
The keyword argument `foo` is a function to run on each method of each generic function in the module.
`foo` defaults to `check_return_value`.

    check_function(f::Function;foo=check_return_value)

The function `check_function` takes a generic Function as its only positional argument.
The keyword argument `foo` is a function to run on each method of `f`.
`foo` should take a function and it's type signature (the arguments to `code_typed` and friends);
it defaults to `check_return_value`.
