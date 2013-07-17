function isabstract(dt::DataType)
  length(subtypes(dt)) != 0
end

function iswobbly(dt::DataType)
  isabstract(dt)
end

function iswobbly(ut::UnionType)
  true
end

function returnbasedonvalues(args...)
  e = finfer(args...)
  body = e.args[3]
  argnames = e.args[1]
  argtuples = e.args[2][2]
  argtypes = DataType[]
  for (sym,typ,x) in argtuples
    if contains(argnames,sym)
      push!(argtypes,typ)
    end
  end

  if !iswobbly(body.typ) return false end
  for typ in argtypes
    if iswobbly(typ) # this is an "isabstract"||"isunion" test
      return false
    end
  end
  return true # return is not concrete type; all args are concrete types
end

