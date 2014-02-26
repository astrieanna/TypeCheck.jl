function Base.code_typed(f::Function)
  Expr[code_typed(m) for m in f.env]
end

function Base.code_typed(m::Method)
 linfo = m.func.code
 (tree,ty) = Base.typeinf(linfo,m.sig,())
 if !isa(tree,Expr)
     ccall(:jl_uncompress_ast, Any, (Any,Any), linfo, tree)
  else
    tree
  end
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
function returntype(e::Expr,context::Expr) #must be :call,:new,:call1
  if Base.is_expr(e,:new); return e.typ; end
  if Base.is_expr(e,:call1) && isa(e.args[1], TopNode); return e.typ; end
  if !Base.is_expr(e,:call); error("Expected :call Expr"); end

  if is_top(e)
    return e.typ
  end

  callee = e.args[1]
  if is_top(callee)
    return returntype(callee,context)
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
      fargtypes = tuple([argtype(ea,context) for ea in e.args[2:end]])
      return Union([returntype(ef) for ef in code_typed(f,fargtypes)]...)
    else
      return @show e.typ
    end
  end

  return e.typ
end

function argtype(e::Expr,context::Expr)
 if Base.is_expr(e,:call) || Base.is_expr(e,:new) || Base.is_expr(e,:call1)
   return returntype(e,context)
 end

 @show e
 return Any
end
function argtype(s::Symbol,e::Expr)
  vartypes = [x[1] => x[2] for x in e.args[2][2]]
  s in vartypes ? (vartypes[@show s]) : Any
end
argtype(s::SymbolNode,e::Expr) = s.typ
argtype(t::TopNode,e::Expr) = Any
argtype(l::LambdaStaticData,e::Expr) = Function
argtype(q::QuoteNode,e::Expr) = argtype(q.value,e)

#TODO: how to deal with immediate values
argtype(n::Number,e::Expr) = typeof(n)
argtype(c::Char,e::Expr) = typeof(c)
argtype(s::String,e::Expr) = typeof(s)
argtype(i,e::Expr) = typeof(i)

Base.start(t::DataType) = [t]
function Base.next(t::DataType,arr::Vector{DataType})
  c = pop!(arr)
  append!(arr,[x for x in subtypes(c)])
  (c,arr)
end
Base.done(t::DataType,arr::Vector{DataType}) = length(arr) == 0

function methodswithsubtypes(t::DataType;onlyleaves::Bool=false,lim::Int=10)
  d = Dict{Symbol,Int}()
  count = 0
  for s in t
    if !onlyleaves || (onlyleaves && isleaftype(s))
      count += 1
      fs = Set{Symbol}()
      for m in methodswith(s)
        push!(fs,m.func.code.name)
      end
      for sym in fs
        d[sym] = get(d,sym,0) + 1
      end
    end
  end
  l = [(k,v/count) for (k,v) in d]
  sort!(l,by=(x->x[2]),rev=true)
  l[1:min(lim,end)]
end
