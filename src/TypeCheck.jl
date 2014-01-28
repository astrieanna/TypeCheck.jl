# These are some functions to allow static type-checking of Julia programs

module TypeCheck
  export check_all_module, check_function, check_loop_types, check_return_value

  include("Helpers.jl")

  # check all the methods of a generic function
  function _check_function(f;foo=check_return_value,kwargs...) #f should be a generic function
    #@show f
    results = [tuple(e,foo(e;kwargs...)...) for e in code_typed(f)]
    presults = [("\t($(string_of_argtypes(argtypes(r[1]))))$(r[2])",r[3]) for r in results]
    presults = [r[1] for r in filter(x-> x[2], presults)]
    #presults = [r[1] for r in presults]
    (presults,length(presults))
  end

  function check_function(f;kwargs...)
    (results,count) = _check_function(f;kwargs...)
    print(results)
  end
  
  # check all the generic functions in a module
  function check_all_module(m::Module;kwargs...)
    score = 0
    for n in names(m)
      try
        f = eval(m,n)
        if isgeneric(f) && typeof(f) == Function
          (lines,count) = _check_function(f;kwargs...)
          score += count
          if !isempty(lines)
            println("$n:")
            for l in lines println(l) end
          end
        end
      catch e
        println("$n: $e")
      end
    end
    println("The total number of failed methods in $m is $score")
  end


## Checking that return values are base only on input *types*, not values.

  function check_return_value(e::Expr;kwargs...)
    (typ,b) = returnbasedonvalues(e;kwargs...)
    return b ? ("::$typ failed",b) : ("::$typ passed",b)
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
    lines = {}
    for i in 1:length(b)
      if typeof(b[i]) == LabelNode
        l = b[i].label
        jumpback = findnext(x-> typeof(x) == GotoNode && x.label == l, b, i)
        if jumpback != 0
          #println("$i: START LOOP: ends at $jumpback")
          push!(loops,jumpback)
          nesting += 1
        end
      end

      if nesting > 0
        #if typeof(b[i]) == Expr
        #  println("$i: \t", b[i])
        #elseif typeof(b[i]) == LabelNode || typeof(b[i]) == GotoNode
        #  println("$i: ", typeof(b[i]), " ", b[i].label)
        #elseif typeof(b[i]) != LineNumberNode
        #  println("$i: ", typeof(b[i]))
        #end
        push!(lines,(i,b[i]))
      end

      if typeof(b[i]) == GotoNode && in(i,loops)
        splice!(loops,findfirst(loops,i))
        nesting -= 1
        #println("$i: END LOOP: jumps to ",b[i].label)
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
