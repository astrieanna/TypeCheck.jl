function Base.code_typed(f::Function)
  lengths = Set(Int64[length(m.sig) for m in f.env]...)
  vcat([code_typed(f, tuple([Any for x in 1:l]...)) for l in lengths]...)
end

function _whos(e::Expr)
  vars = sort(e.args[2][2];by=x->x[1])
  [println("\t",x[1],"\t",x[2]) for x in vars]
end

function Base.whos(f,args...)
  for e in code_typed(f,args...)
    println(signature(e))
    _whos(e)                                
    println("")
  end
end

returntype(e::Expr) =  e.args[3].typ
body(e::Expr) = e.args[3].args
returns(e::Expr) = filter(x-> typeof(x) == Expr && x.head==:return,body(e))
call_info(call::Expr) = (call.args[1], AType[expr_type(e) for e in call.args[2:end]])

function signature(e::Expr)
  r = returntype(e) 
 "($(string_of_argtypes(argtypes(e))))::$(r)"
end
  
function extract_calls_from_returns(e::Expr)
  rs = returns(e)
  rs_with_calls = filter(x->typeof(x.args[1]) == Expr && x.args[1].head == :call,rs)
  Expr[expr.args[1] for expr in rs_with_calls]
end

AType = Union(Type,TypeVar)

# for a function, get the types of each of the arguments in the signature
function argtypes(e::Expr)
  argnames = Symbol[typeof(x) == Symbol ? x : x.args[1] for x in e.args[1]]
  argtuples = filter(x->x[1] in argnames, e.args[2][2]) #only arguments, no local vars
  AType[t[2] for t in argtuples]
end

function string_of_argtypes(arr::Vector{AType})
  join([string(a) for a in arr],",")
end

is_top(e) = Base.is_expr(e,:call) && typeof(e.args[1]) == TopNode
function find_returntype(e::Expr) #must be :call,:new,:call1
  if Base.is_expr(e,:new); return e.typ; end
  if Base.is_expr(e,:call1) && isa(e.args[1], TopNode); return e.typ; end
  if !Base.is_expr(e,:call); error("Expected :call Expr"); end

  if is_top(e)
    return e.typ
  end

  callee = e.args[1]
  if is_top(callee)
    return find_returntype(callee)
  elseif isa(callee,SymbolNode) # only seen (func::F), so non-generic function
    return Any
  elseif is(callee,Symbol)
    if e.typ != Any || any([isa(x,LambdaStaticData) for x in e.args[2:end]])
      return e.typ
    end

    if isdefined(Base,callee)
      f = eval(Base,callee)
      if !isa(f,Function) || !isgeneric(f)
        return e.typ
      end
      fargtypes = tuple([find_argtype(ea) for ea in e.args[2:end]])
      return Union([returntype(ef) for ef in code_typed(f,fargtypes)]...)
    else
      return @show e.typ
    end
  end

  return e.typ
end

function find_argtype(e::Expr)
 if Base.is_expr(e,:call) || Base.is_expr(e,:new) || Base.is_expr(e,:call1)
   return find_returntype(e)
 end

 @show e
 return Any
end
find_argtype(s::Symbol) = Any #TODO: try looking up symbols
find_argtype(s::SymbolNode) = Any
find_argtype(t::TopNode) = Any
find_argtype(l::LambdaStaticData) = Function
find_argtype(q::QuoteNode) = find_argtype(q.value)

#TODO: how to deal with immediate values
find_argtype(e::Number) = typeof(e)
find_argtype(e::Char) = typeof(e)
find_argtype(e::String) = typeof(e)
find_argtype(i) = typeof(i)
