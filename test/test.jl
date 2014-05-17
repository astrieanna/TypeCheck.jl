module TestTypeCheck
  using TypeCheck, FactCheck
 
  istype(t) = isa(t,TypeCheck.AType)
 
  facts("Check Return Types: Make Sure It Runs on Base") do
    for n in names(Base)
      if isdefined(Base,n)
        f = eval(Base,n)
        if isgeneric(f) && typeof(f) == Function
          context(string(n)) do
            @fact TypeCheck.checkreturntypes(f) => anything # => FunctionSignature([],Symbol)
            [@fact istype(TypeCheck.returntype(e)) => true for e in code_typed(f)]
            [@fact TypeCheck.returntype(e) => istype for e in code_typed(f)]
          end
        end
      else
        @fact n => x->isdefined(Base,x)
      end
    end
  end

  caught(x) = x[2] == true
  notcaught(x) = x[2] == false
  function checkreturn(f,check)
    @fact length(code_typed(f)) => 1
    @fact TypeCheck.checkreturntype(code_typed(f)[1]) => check
  end

  facts("Check Return Types: True Positives") do
    barr(x::Int) = isprime(x) ? x : false
    checkreturn(barr, caught)
  end

  facts("Check Return Types: False Negatives") do
    foo(x::Any) = isprime(x) ? x : false
    checkreturn(foo, notcaught)
  end


  facts("Check Loop Types: Make Sure It Runs on Base") do
    for n in names(Base)
      if isdefined(Base,n)
        f = eval(Base,n)
        if isgeneric(f) && typeof(f) == Function
          context(string(n)) do
            @fact TypeCheck.checklooptypes(f) => anything # => LoopResults
          end
        end
      else
        @fact n => x->isdefined(Base,x)
      end
    end
  end

  passed(x) = isempty(x.methods)
  failed(x) = !passed(x)
  function checkloops(f,check)
    @fact length(code_typed(f)) => 1
    @fact checklooptypes(f) => check
  end

  facts("Check Loop Types: True Positives") do
    function f1(x::Int)
      for n in 1:x
        x /= n
      end
      return x
    end
    checkloops(f1,failed)
  end

  facts("Check Loop Types: True Negatives") do
    function g1()
      x::Int = 5
      for i = 1:100
        x *= 2.5
      end
      return x
    end
    checkloops(g1,passed)
    function g2()
      x = 5
      x = 0.2
      for i = 1:10
        x *= 2
      end
      return x
    end
    checkloops(g2,passed)
  end


  facts("Check Method Calls: Make Sure It Runs on Base") do
    for n in names(Base)
      if isdefined(Base,n)
        f = eval(Base,n)
        if isgeneric(f) && typeof(f) == Function
          context(string(n)) do
            @fact TypeCheck.checkmethodcalls(f) => anything # => FunctionCalls
          end
        end
      else
        @fact n => x->isdefined(Base,x)
      end
    end
  end

  facts("Check Method Calls: True Positives") do
  end

  facts("Check Method Calls: False Negatives") do
  end

  facts("find_lhs_variables") do
    function lhs1(x::Int)
      x = 5
      return y
    end
    @fact TypeCheck.find_lhs_variables(code_typed(lhs1,(Int,))[1]) => Set{Symbol}([:x])

    function lhs2()
      y = 5
      true && (x = 42)
      foo(y) && (z = 55)
      return y
    end
    @fact TypeCheck.find_lhs_variables(code_typed(lhs2,())[1]) => Set{Symbol}([:x,:y,:z])
  end

  facts("find_rhs_variables") do
    function rhs1(x::Int)
      x = 5
      return y
    end
    @fact TypeCheck.find_rhs_variables(code_typed(rhs1,(Int,))[1]) => Set{Symbol}([:y])
    
    function rhs2()
      y = 5
      true && (x = 42)
      foo(y) && (z = 55)
      return y
    end
    @fact TypeCheck.find_rhs_variables(code_typed(rhs2,())[1]) => Set{Symbol}([:y])

    function rhs3()
      y = 5
      true && (x = y)
      foo(y) && (z += y)
      return w
    end
    @fact TypeCheck.find_rhs_variables(code_typed(rhs3,())[1]) => Set{Symbol}([:w,:y,:z])
  end

  exitstatus()
end
