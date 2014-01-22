AtomicType = Union(DataType,UnionType,TypeVar,TypeConstructor,())
AType = Union(AtomicType,(AtomicType,),(AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType),
              (AtomicType,AtomicType,AtomicType,AtomicType))

function Base.code_typed(f::Function)
  lengths = Set(Int64[length(m.sig) for m in f.env]...)
  vcat([code_typed(f, tuple([Any for x in 1:l]...)) for l in lengths]...)
end
  
returntype(e::Expr) =  e.args[3].typ
body(e::Expr) = e.args[3].args
returns(e::Expr) = Expr[filter(x-> typeof(x) == Expr && x.head==:return,es) for es in body(e)]

function extract_calls_from_returns(e::Expr)
  rs = returns(e)
  rs_with_calls = filter(x->typeof(x.args[1]) == Expr && x.args[1].head == :call,rs)
  Expr[expr.args[1] for expr in rs_with_calls]
end

# for a function, get the types of the arguments for each call inside a return
#argtypes(e::Expr) = [Symbol[expr_type(e) for e in call.args[2:]] for call in extract_calls_from_returns(e)]

# for a function, get the types of each of the arguments in the signature
function argtypes(e::Expr)
  argtuples = filter(x->x[1] in e.args[1], e.args[2][2]) #only arguments, no local vars
  AType[t[2] for t in argtuples]
end

function string_of_argtypes(arr::Vector{AType})
  join([string(a) for a in arr],",")
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

