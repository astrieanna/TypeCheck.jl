## Check Return Types

It is good style in Julia for the return type of a function to only depend on the types of the arguments and not on their values.
The following, for example, is not desirable:

    function foo(x::Int)
      if x > 5
        return x
      else
        return false
      end
    end

The return type of the function would be inferred to be `Union(Int64,Bool)`.

Until now, there has been no way to check that functions do not behave in this way, other than code review.
I have written a static checker to detect that this invariant may be violated.
