function returnbasedonvalues(args...)
  e = finfer(args...)
  body = e.args[3]
  if isleaftype(body.typ) return false end

  argnames = e.args[1]
  argtuples = e.args[2][2]
  for (sym,typ,x) in argtuples
    if contains(argnames,sym) && (!isleaftype(typ))
      return false
    end
  end

  return true # return is not concrete type; all args are concrete types
end

