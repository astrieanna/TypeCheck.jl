# These are some functions to allow static type-checking of Julia programs

module TypeCheck
  export check_all_module, check_function, check_loop_types, check_return_value

  # check all the methods of a generic function
  function check_function(f;foo=check_return_value) #f should be a generic function
    i = 0
    lines = ASCIIString[]
    count = 0
    for m in f.env
      ll = foo(f,m.sig)
      if !isempty(ll)
        ll[1] = "\t$(m.sig):" * ll[1]
        count += 1
        append!(lines,ll)
      end
      i += 1
    end
    (lines,count)
  end
  
  # check all the generic functions in a module
  function check_all_module(m::Module;foo=check_return_value)
    score = 0
    for n in names(m)
      try
        f = eval(m,n)
        if isgeneric(f)
          (lines,count) = check_function(f;foo=foo)
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

  function check_return_value(args...)
    lines = ASCIIString[]
    (typ,b) = returnbasedonvalues(args...;istrunion=true)
    if b
      push!(lines,"::$typ failed")
    end
    lines
  end
  
  # The goal of this function is, given one method of a generic function,
  # determine whether it's return type might change based on input values rather than input types
  # It takes the same arguments as code_typed
  function returnbasedonvalues(args...;istrunion=false,ibytestring=false)
    e = code_typed(args...)[1] #why does this return an array? when would it be of size != 1?
    body = e.args[3]
    if isleaftype(body.typ) || body.typ == None return (body.typ,false) end
    if istrunion && body.typ == Union(ASCIIString, UTF8String) return (body.typ,false) end
    if ibytestring && body.typ == ByteString return (body.typ,false) end
  
    argnames = map(x -> isa(x,Symbol) ? x : x.args[1],e.args[1])
    argtuples = e.args[2][2]
    for (sym,typ,x) in argtuples
      if in(sym,argnames) && (!isleaftype(typ))
        return (body.typ,false)
      end
    end
  
    return (body.typ,true)
    # return is not concrete type; all args are concrete types
    # what about functions that return an abstract type for other reasons? (bytestring)
    # what about functions that are just not type-inferred well enough?
    # if a function takes no arguments, should we return true or false?
  end


## Checking that variables in loops have concrete types that do not vary
  
  check_loop_types(args...) = find_loose_types(loopcontents(args...))
  
  # This is a function for trying to detect loops in a method of a generic function
  # It takes the same arguments as code_typed
  # And returns the lines that are inside one or more loops
  function loopcontents(args...)
    e = code_typed(args...)[1]
    body = e.args[3].args
    loops = Int[]
    nesting = 0
    lines = {}
    for i in 1:length(body)
      if typeof(body[i]) == LabelNode
        l = body[i].label
        jumpback = findnext(x-> typeof(x) == GotoNode && x.label == l, body, i)
        if jumpback != 0
          #println("$i: START LOOP: ends at $jumpback")
          push!(loops,jumpback)
          nesting += 1
        end
      end

      if nesting > 0
        #if typeof(body[i]) == Expr
        #  println("$i: \t", body[i])
        #elseif typeof(body[i]) == LabelNode || typeof(body[i]) == GotoNode
        #  println("$i: ", typeof(body[i]), " ", body[i].label)
        #elseif typeof(body[i]) != LineNumberNode
        #  println("$i: ", typeof(body[i]))
        #end
        push!(lines,(i,body[i]))
      end

      if typeof(body[i]) == GotoNode && in(i,loops)
        splice!(loops,findfirst(loops,i))
        nesting -= 1
        #println("$i: END LOOP: jumps to ",body[i].label)
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
    isempty(lines) ? lines : unshift!(lines,"")
  end

## Check method calls

  check_method_calls(args...) = check_methods_exist(find_method_calls(args...))
  
  function check_methods_exist(arr)
    lines = ASCIIString[]
    for e in arr
      push!(lines,"\t\t$(show(e))")
    end
    lines
  end

  function find_method_calls(args...)
    e = code_typed(args...)[1]
    body = e.args[3].args
    lines = {}
    for b in body
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
