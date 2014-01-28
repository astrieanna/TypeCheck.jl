# These are some functions to allow static type-checking of Julia programs

module TypeCheck
  export check_all_module, check_loop_types, check_return_value

  include("Helpers.jl")

  # check all the generic functions in a module
  function check_all_module(m::Module;test=check_return_value,kwargs...)
    score = 0
    for n in names(m)
      f = eval(m,n)
      if isgeneric(f) && typeof(f) == Function
        fm = test(f;kwargs...)
        score += length(fm.methods)
        display(fm)
      end
    end
    println("The total number of failed methods in $m is $score")
  end

  type MethodSignature
    typs::Vector{AType}
    returntype::Type
  end

  type FunctionSignature
    methods::Vector{MethodSignature}
    name::Symbol
  end

  Base.writemime(io, ::MIME"text/plain", x::MethodSignature) = println(io,"(",string_of_argtypes(x.typs),")::",x.returntype)
  function Base.writemime(io, ::MIME"text/plain", x::FunctionSignature)
    for m in x.methods
      print(io,string(x.name))
      display(m)
    end
  end

## Checking that return values are base only on input *types*, not values.

  check_return_values(m::Module;kwargs...) = check_all_module(m;test=check_return_values,kwargs...)

  function check_return_values(f::Function;kwargs...)
    results = [check_return_value(e;kwargs...) for e in code_typed(f)]
    results = [r[1] for r in filter(x-> x[2], results)]
    FunctionSignature(results,f.env.name)
  end

  function check_return_value(e::Expr;kwargs...)
    (typ,b) = returnbasedonvalues(e;kwargs...)
    (MethodSignature(argtypes(e),typ),b)
  end
  
  # The goal of this function is, given one method of a generic function,
  # determine whether it's return type might change based on input values rather than input types
  function returnbasedonvalues(e::Expr;istrunion=false,ibytestring=false)
    rt = returntype(e)
    ts = argtypes(e)

    if isleaftype(rt) || rt == None return (rt,false) end
    if istrunion && rt == Union(ASCIIString,UTF8String) return (rt,false) end
    if ibytestring && rt == ByteString return (rt,false) end

    for t in ts
     if !isleaftype(t)
       return (rt,false)
     end
    end

    cs = [expr_type(c) for c in extract_calls_from_returns(e)]
    for c in cs
      if rt == c
         return (rt,false)
      end
    end

    #@show cs
    return (rt,true) # return is not concrete type; all args are concrete types
  end
    # what about functions that return an abstract type for other reasons? (bytestring)
    # what about functions that are just not type-inferred well enough?
    # if a function takes no arguments, should we return true or false?


## Checking that variables in loops have concrete types that do not vary
  
  check_loop_types(e::Expr) = find_loose_types(loopcontents(e))
  
  # This is a function for trying to detect loops in a method of a generic function
  # And returns the lines that are inside one or more loops
  function loopcontents(e)
    b = body(e)
    loops = Int[]
    nesting = 0
    lines = Union(Expr,LabelNode)[] 
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

  function find_loose_types(arr::Vector)
    lines = ASCIIString[]
    for (i,e) in arr
      if typeof(e) == Expr
        es = copy(e.args)
        while !isempty(es)
          e1 = pop!(es)
          if typeof(e1) == Expr
            append!(es,e1.args)
          elseif typeof(e1) == SymbolNode && !isleaftype(e1.typ) && typeof(e1.typ) == UnionType
            push!(lines,"\t\t$i: $(e1.name): $(e1.typ)")
          end 
        end                          
      end
    end
    return isempty(lines) ? (lines,false) : (unshift!(lines,""),true)
  end

## Check method calls

  check_method_calls(e) = check_methods_exist(find_method_calls(e))
  
  function check_methods_exist(arr)
    lines = ASCIIString[""]
    for e in arr
      append!(lines,["\t\t$s" for s in split("$e",['\n'])])
    end
    lines
  end

  function find_method_calls(e)
    bod = body(e)
    lines = {}
    for b in bod
      if typeof(b) == Expr
        if b.head == :return
          append!(body,b.args)
        elseif b.head == :call
          push!(lines,b.args)
        end 
      end
    end
    lines
  end

end  #end module
