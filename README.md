TypeCheck.jl
============
[![Build Status](https://travis-ci.org/astrieanna/TypeCheck.jl.png?branch=master)](https://travis-ci.org/astrieanna/TypeCheck.jl)

Type-based static analysis for the Julia programming language.

There are three main checks you can run: `check_return_types`, `check_loop_types`, and `check_method_calls`.
Running a check on a function checks each method; running a check on a module checks each function (by checking each method of each function).

1. **`check_return_types`**: do the return types of your functions depend on the types, not the values of your arguments?

    You can run this on a generic function or on a module:
    * `check_return_types(istext)`
    * `check_return_types(Base)`

2. **`check_loop_types`**: do the variables in your loops have stable types?

    A common performance problem is having unstable (numeric) variable types in an important loop.
    Having stable types within loops allows Julia's JIT compiler to output code as fast as a static compiler;
    having unstable types means resorting to slower, dynamic code.

    You can run this on a generic function or on a module:
    * `check_loop_types(sort)`
    * `check_loop_types(Base)`

3. **`check_method_calls`**: could your functions have run-time NoMethodErrors?

    `NoMethodError`s are probably the most common error in Julia. This is an attempt to find them statically.

    You can run this on a generic function or on a module:
    * `check_method_calls(sort)`
    * `check_method_calls(Base)`


If you want to run these only on a single method, you can get the `Expr` for the method from `code_typed` and then pass that into the check you would like to run.

This package also defined `code_typed(f::Function` to get the Expr for each method of a function and `whos(f::Function` to get a listing of the names and types of all the variables in the function.
