function returnbasedonvalues(args...)
  e = finfer(args...)
  body = e.args[3]
  if isleaftype(body.typ) return false end

  argnames = map(x -> isa(x,Symbol) ? x : x.args[1],e.args[1])
  argtuples = e.args[2][2]
  for (sym,typ,x) in argtuples
    if contains(argnames,sym) && (!isleaftype(typ))
      return false
    end
  end

  return true # return is not concrete type; all args are concrete types
  # what about functions that return an abstract type for other reasons? (bytestring)
  # what about functions that are just not type-inferred well enough?
  # if a function takes no arguments, should we return true or false?
end

# make MethodTable iterable. I like foreach loops. :)
Base.start(mt::MethodTable)           = mt.defs
Base.next(mt::MethodTable, m::Method) = (m,m.next)
Base.done(mt::MethodTable, m::Method) = false 
Base.done(mt::MethodTable, i::())     = true

# check all the methods of a generic function
function check_function(f) #f should be a generic function
  i = 0
  for m in f.env
    if returnbasedonvalues(f,m.sig)
      println("$(f.env.name)$(m.sig) failed")
    end
    i += 1
  end
end

# check all the generic functions in a module
function check_all_module(m::Module)
  for n in names(m)
    try
      f = eval(n) # this fails for Modules != Base
      if isgeneric(f)
        check_function(f)
      end
    catch e
      println(e)
    end
  end
end

