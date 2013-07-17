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

  if isleaftype(body.typ) return false end
  for typ in argtypes
    if !isleaftype(typ)
      return false
    end
  end
  return true # return is not concrete type; all args are concrete types
end

