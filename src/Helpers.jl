
AType = Union(DataType,UnionType)

# the return type of a method(s) of a generic function
function returntype(f,args...)
  AType[e.args[3].typ for e in code_typed(f,args...)]
end

# the expressions in the body of a method(s) of a generic function
# returns an array of arrays
#returned array could contain Exprs, Symbols, Ints, TopNodes, etc
body(f,args...) = [e.args[3].args for e in code_typed(f,args...)]

# the return statements in a method(s) of a generic function
returns(f,args...) = Array{Expr,1}[filter(x-> typeof(x) == Expr && x.head==:return,es) for es in body(f,args...)]

# given the return statements from a generic function, pull out the :calls from them.
function extract_calls_from_returns(returns_arrs)
  output = Array(Vector{Expr},length(returns_arrs))
  for i in 1:length(returns_arrs)
    returns_with_calls = filter(x->typeof(x.args[1]) == Expr && x.args[1].head == :call,returns_arrs[i])
    output[i] = [expr.args[1] for expr in returns_with_calls]
  end
  output
end

# Given the output of extract_calls, find the types of the arguments to each one
function argtypes(callss::Array{Array{Any,1},1})
  output = Array(Vector{Vector{Union(DataType,UnionType,Symbol)}},length(callss))
  for i in 1:length(callss)
    output[i] = [Symbol[expr_type(e) for e in call.args[2:]] for call in callss[i]]
  end
  output
end

# Given an expression, return it's type when used in a method call
function expr_type(expr)
  if typeof(expr) == Symbol
    return Any
  elseif typeof(expr) == TopNode
    return Any
  elseif typeof(expr) == Expr
    if expr.head == :call && typeof(expr.args[1]) == TopNode && expr.args[1].name == :box
      return eval(expr.args[2]) #the type being cast to, if top(box)
    end
    return Any ## TODO: fix me!
  else
    return typeof(expr)
  end
end

# Given a method(s) of a generic function, find the types of the arguments to each method
function argtypes(f,args...)
  exprs = code_typed(f,args...)
  out = Array(Vector{Union(UnionType,DataType)},length(exprs))
  for i in 1:length(exprs)
    argnames = exprs[i].args[1]
    vartuples = exprs[i].args[2][2] #vector of (name,type,int)
    argtuples = filter(x->x[1] in argnames, vartuples) #only arguments, no local vars
    out[i] = Union(DataType,UnionType)[t[2] for t in argtuples]
  end
  return out
end

function Base.code_typed(f::Function)
  lengths = Set(Int64[length(m.sig) for m in f.env]...)
  vcat([code_typed(f, tuple([Any for x in 1:l]...)) for l in lengths]...)
end
  
