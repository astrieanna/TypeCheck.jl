## Check Loop Types

In Julia, for-loops are generally the fastest way to write code.
(Faster than vectorized code; faster than maps or folds.)
An easy way to ruin their performance is to change the type of a variable inside a tight loop.
If all the variables in a loop have stable types, then the code Julia outputs will be the same tight, fast code as a strictly typed language.
However, slower dynamic code will be produced for any variable with an unstable type.

It can be very easy to run afoul of this:

    x = 5 # x is an Int
    for i=1:1000
     x += 100
     x /= 2 # x is a Float64
    end
    # x is a Float64

In this code example,  `x` begins life as an `Int`.
In the first iteration of the loop, `x += 100` takes `x` as  an `Int` and returns an `Int`;
`x /= 2` takes this new `Int` and returns a `Float64`. 
After this, `x` will be a `Float64` for all the remaining iterations of the loop.
This means that the extra dynamic code that is needed to handle the dual cases slows down all the iterations, despite only being needed for the first one.
This can be fixed by making `x` a `Float64` from the start: `x = 5.0`.

This can be detected in generic functions by looking at the output of `code_typed`.
Since loops are lowered to gotos, this detection needs to first find loops and then check the types of the variables involved.
Finding loops can be as simple as looking for gotos that jump backwards in the function; ones whos labels precede them.
For each instruction inside this jump backwards, we just need to look at the inferred type of any variables involved.
If the inferred type is a UnionType (or not a leaf type, in general), then the type is unstable.

### Henchmen Unrolling

For the code snippet included above, the compiler could use another optimization to fix the problem.
A technique called Henchmen Unrolling involves unrolling some iterations of a loop.
In this case, unrolling the first iteration will cause the type to stabalize and the loop code to become fast and statically typed.

The current loop type checking code may or may not get a false positive with this optimization enabled; since we're using variable's types, they might still fluctuate.
