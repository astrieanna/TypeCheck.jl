## Check Method Calls

The most obviously useful kind of type checking in Julia is to prevent "No Method Error"s.
This presents a challenge:
methods are often added to generic functions after the fact in Julia,
so this checking must be done with as much awareness as possible
of the environment in which the call will be made in order to avoid false positives.

I have not yet implemented this because I don't know how to get into the proper context to make the check.
I could write first version which ignores this problem.
