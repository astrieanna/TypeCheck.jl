# These are some functions to allow static type-checking of Julia programs

module TypeCheck
  export check_return_types, check_loop_types, check_method_calls,
    methodswithdescendants

  include("Helpers.jl")

  # check all the generic functions in a module
  function check_all_module(m::Module;test=check_return_types,kwargs...)
    score = 0
    for n in names(m)
      f = eval(m,n)
      if isgeneric(f) && typeof(f) == Function
        fm = test(f;mod=m,kwargs...)
        score += length(fm.methods)
        display(fm)
      end
    end
    println("The total number of failed methods in $m is $score")
  end

  type MethodSignature
    typs::Vector{AType}
    returntype::Union(Type,TypeVar) # v0.2 has TypeVars as returntypes; v0.3 does not
  end
  MethodSignature(e::Expr) = MethodSignature(argtypes(e),returntype(e))
  Base.writemime(io, ::MIME"text/plain", x::MethodSignature) = println(io,"(",string_of_argtypes(x.typs),")::",x.returntype)

## Checking that return values are base only on input *types*, not values.

  type FunctionSignature
    methods::Vector{MethodSignature}
    name::Symbol
  end

  function Base.writemime(io, ::MIME"text/plain", x::FunctionSignature)
    for m in x.methods
      print(io,string(x.name))
      display(m)
    end
  end

  check_return_types(m::Module;kwargs...) = check_all_module(m;test=check_return_types,kwargs...)

  function check_return_types(f::Function;kwargs...)
    results = MethodSignature[]
    for e in code_typed(f)
      (ms,b) = check_return_type(e;kwargs...)
      if b push!(results,ms) end
    end
    FunctionSignature(results,f.env.name)
  end

  function check_return_type(e::Expr;kwargs...)
    (typ,b) = isreturnbasedonvalues(e;kwargs...)
    (MethodSignature(argtypes(e),typ),b)
  end
  
  # Determine whether this method's return type might change based on input values rather than input types
  function isreturnbasedonvalues(e::Expr;mod=Base)
    rt = returntype(e)
    ts = argtypes(e)

    if isleaftype(rt) || rt == None return (rt,false) end

    for t in ts
     if !isleaftype(t)
       return (rt,false)
     end
    end

    cs = [returntype(c,e) for c in extract_calls_from_returns(e)]
    for c in cs
      if rt == c
         return (rt,false)
      end
    end

    return (rt,true) # return is not concrete type; all args are concrete types
  end

## Checking that variables in loops have concrete types
  
  type LoopResult
    msig::MethodSignature
    lines::Vector{(Symbol,Type)} #TODO should this be a specialized type? SymbolNode?
    LoopResult(ms::MethodSignature,ls::Vector{(Symbol,Type)}) = new(ms,unique(ls))
  end

  function Base.writemime(io, ::MIME"text/plain", x::LoopResult)
    display(x.msig)
    for (s,t) in x.lines
      println(io,"\t",string(s),"::",string(t))
    end
  end

  type LoopResults
    name::Symbol
    methods::Vector{LoopResult}
  end

  function Base.writemime(io, ::MIME"text/plain", x::LoopResults)
    for lr in x.methods
      print(io,string(x.name))
      display(lr)
    end
  end

  check_loop_types(m::Module) = check_all_module(m;test=check_loop_types)

  function check_loop_types(f::Function;kwargs...)
    lrs = LoopResult[]
    for e in code_typed(f)
      lr = check_loop_types(e)
      if length(lr.lines) > 0 push!(lrs,lr) end
    end
    LoopResults(f.env.name,lrs)
  end

  check_loop_types(e::Expr;kwargs...) = loosetypes(e,loopcontents(e))
  
  # This is a function for trying to detect loops in a method of a generic function
  # Returns lines that are inside one or more loops
  function loopcontents(e)
    b = body(e)
    loops = Int[]
    nesting = 0
    lines = {}
    for i in 1:length(b)
      if typeof(b[i]) == LabelNode
        l = b[i].label
        jumpback = findnext(x-> typeof(x) == GotoNode && x.label == l, b, i)
        if jumpback != 0
          push!(loops,jumpback)
          nesting += 1
        end
      end

      if nesting > 0
        push!(lines,(i,b[i]))
      end

      if typeof(b[i]) == GotoNode && in(i,loops)
        splice!(loops,findfirst(loops,i))
        nesting -= 1
      end
    end
    lines
  end

  # Looks for variables with non-leaf types
  function loosetypes(method::Expr,lr::Vector)
    lines = (Symbol,Type)[]
    for (i,e) in lr
      if typeof(e) == Expr
        es = copy(e.args)
        while !isempty(es)
          e1 = pop!(es)
          if typeof(e1) == Expr
            append!(es,e1.args)
          elseif typeof(e1) == SymbolNode && !isleaftype(e1.typ) && typeof(e1.typ) == UnionType
            push!(lines,(e1.name,e1.typ))
          end 
        end                          
      end
    end
    return LoopResult(MethodSignature(method),lines)
  end

## Check method calls

  type CallSignature
    name::Symbol
    argtypes::Vector{AType}
  end
  Base.writemime(io, ::MIME"text/plain", x::CallSignature) = println(io,string(x.name),"(",string_of_argtypes(x.argtypes),")")

  type MethodCalls
    m::MethodSignature
    calls::Vector{CallSignature}
  end

  function Base.writemime(io, ::MIME"text/plain", x::MethodCalls)
    display(x.m)
    for c in x.calls
      print(io,"\t")
      display(c)
    end
  end

  type FunctionCalls
    name::Symbol
    methods::Vector{MethodCalls}
  end

  function Base.writemime(io, ::MIME"text/plain", x::FunctionCalls)
    for mc in x.methods
      print(io,string(x.name))
      display(mc)
    end
  end

  check_method_calls(m::Module) = check_all_module(m;test=check_method_calls)

  function check_method_calls(f::Function;kwargs...)
    calls = MethodCalls[] 
    for m in f.env
      e = code_typed(m)
      mc = check_method_calls(e,m;kwargs...)
      if !isempty(mc.calls)
        push!(calls, mc)
      end
    end
    FunctionCalls(f.env.name,calls)
  end

  function check_method_calls(e::Expr,m::Method;kwargs...)
    if Base.arg_decl_parts(m)[3] == symbol("deprecated.jl")
      CallSignature[]
    end
    no_method_errors(e,method_calls(e);kwargs...)
  end

  # Find any methods that match the given CallSignature
  function hasmatches(mod::Module,cs::CallSignature)
    if isdefined(mod,cs.name)
      f = eval(mod,cs.name)
      if isgeneric(f)
        opts = methods(f,tuple(cs.argtypes...))
        if isempty(opts)
          return false
        end
      end
    else
      #println("$mod.$(cs.name) is undefined")
    end
    return true
  end

  # Find any CallSignatures that indicate potential NoMethodErrors 
  function no_method_errors(e::Expr,cs::Vector{CallSignature};mod=Base)
    output = CallSignature[]
    for callsig in cs
      if !hasmatches(mod,callsig)
        push!(output,callsig)
      end
    end
    MethodCalls(MethodSignature(e),output)
  end

  # Look through the body of the function for `:call`s
  function method_calls(e::Expr)
    b = body(e)
    lines = CallSignature[]
    for s in b
      if typeof(s) == Expr
        if s.head == :return
          append!(b, s.args)
        elseif s.head == :call
          if typeof(s.args[1]) == Symbol
            push!(lines,CallSignature(s.args[1], [argtype(e1,e) for e1 in s.args[2:end]]))
          end
        end
      end
    end
    lines
  end

end  #end module
