function returnbasedonvalues(args...)
  e = code_typed(args...)[1] #why does this return an array? when would it be of size != 1?
  body = e.args[3]
  if isleaftype(body.typ) || body.typ == None return (body.typ,false) end

  argnames = map(x -> isa(x,Symbol) ? x : x.args[1],e.args[1])
  argtuples = e.args[2][2]
  for (sym,typ,x) in argtuples
    if contains(argnames,sym) && (!isleaftype(typ))
      return (body.typ,false)
    end
  end

  return (body.typ,true)
  # return is not concrete type; all args are concrete types
  # what about functions that return an abstract type for other reasons? (bytestring)
  # what about functions that are just not type-inferred well enough?
  # if a function takes no arguments, should we return true or false?
end

# check all the methods of a generic function
function check_function(f) #f should be a generic function
  i = 0
  for m in f.env
    (typ,b) = returnbasedonvalues(f,m.sig)
    if b
      println("$(f.env.name)$(m.sig)::$typ failed")
    end
    i += 1
  end
end

# check all the generic functions in a module
function check_all_module(m::Module)
  for n in names(m)
    try
      f = eval(m,n)
      if isgeneric(f)
        check_function(f)
      end
    catch e
      println("$n: $e")
    end
  end
end

