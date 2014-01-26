Types = Union(DataType,UnionType,TypeVar,TypeConstructor,())
AtomicType = Union(Types,(Types,))
AType = Union(AtomicType,(AtomicType,),
              (AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType,AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType,AtomicType,AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType,AtomicType,AtomicType,AtomicType,AtomicType))

istype(t::DataType) = true
istype(t::UnionType) = true
istype(t::TypeVar) = true
istype(t::TypeConstructor) = true
istype(x::(Any,)) = istype(x[1])
istype(x::(Any,Any)) = istype(x[1]) && istype(x[2])
function istype(t) 
  if Base.isType(t) 
    return true
  elseif length(t) == 1
    return false
  elseif tuple(t...) == t
    return all(map(istype,t))
  end
  return false
end

function Base.code_typed(f::Function)
  lengths = Set(Int64[length(m.sig) for m in f.env]...)
  vcat([code_typed(f, tuple([Any for x in 1:l]...)) for l in lengths]...)
end
  
returntype(e::Expr) =  e.args[3].typ
body(e::Expr) = e.args[3].args
returns(e::Expr) = filter(x-> typeof(x) == Expr && x.head==:return,body(e))

function extract_calls_from_returns(e::Expr)
  rs = returns(e)
  rs_with_calls = filter(x->typeof(x.args[1]) == Expr && x.args[1].head == :call,rs)
  Expr[expr.args[1] for expr in rs_with_calls]
end

# get function name and the types of the arguments for a Expr with head :call
call_info(call::Expr) = (call.args[1], AType[expr_type(e) for e in call.args[2:end]])

# for a function, get the types of each of the arguments in the signature
function argtypes(e::Expr)
  argnames = Symbol[typeof(x) == Symbol ? x : x.args[1] for x in e.args[1]]
  argtuples = filter(x->x[1] in argnames, e.args[2][2]) #only arguments, no local vars
  AType[t[2] for t in argtuples]
end

function string_of_argtypes(arr::Vector{AType})
  join([string(a) for a in arr],",")
end

# Given an expression, return it's type when used in a method call
expr_type(s::Symbol) = Any
expr_type(s::SymbolNode) = Any
expr_type(t::TopNode) = Any
expr_type(l::LambdaStaticData) = error("Got LambdaStaticData; you should have pulled the type from the surrounding Expr.")
expr_type(e) = typeof(e)

expr_type(q::QuoteNode) = typeof(@show q)

is_top(e) = Base.is_expr(e,:call) && typeof(e.args[1]) == TopNode

function expr_type(expr::Expr)
  if is_top(expr)
    return expr.typ 
  elseif Base.is_expr(expr,:call)
    if typeof(expr.args[1]) == Expr && is_top(expr.args[1])
      return expr_type(expr.args[1])
    elseif typeof(expr.args[1]) == SymbolNode # (func::F) -- non-generic function
      return Any
    elseif typeof(expr.args[1]) == Symbol
      if expr.typ != Any
        return expr.typ
      elseif LambdaStaticData in [typeof(x) for x in expr.args[2:end]]
        return expr.typ
      end

      local f
      try
        f = eval(Base,expr.args[1]) #TODO: don't use Base here
      catch e
        return expr.typ # symbol not defined errors
      end
      if typeof(f) != Function || !isgeneric(f)
        return expr.typ 
      end
      fargtypes = tuple([expr_type(e) for e in expr.args[2:end]]...)
      us = Union([returntype(e2) for e2 in code_typed(f,fargtypes)]...)
      return us
    end
    @show expr.typ
    return None 
  else
    @show typeof(expr)
    return None 
  end
end

