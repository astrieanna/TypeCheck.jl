module TestTypeCheck
  using TypeCheck, FactCheck
  
  facts("Check Return Types: Make Sure It Runs on Base") do
    for n in names(Base)
      if isdefined(Base,n)
        f = eval(Base,n)
        if isgeneric(f) && typeof(f) == Function
          context(string(n)) do
            @fact TypeCheck._check_function(f) => anything #=> ([],0)
            [@fact TypeCheck.istype(TypeCheck.returntype(e)) => true for e in code_typed(f)]
            [@fact TypeCheck.returntype(e) => TypeCheck.istype for e in code_typed(f)]
          end
        end
      else
        @fact n => x->isdefined(Base,x)
      end
    end
  end

  caught(x) = x[2] == true
  notcaught(x) = x[2] == false
  function check_return(f,check)
    @fact length(code_typed(f)) => 1
    @fact TypeCheck.check_return_value(code_typed(f)[1]) => check
  end

  facts("Check Return Types: True Positives") do
    barr(x::Int) = isprime(x) ? x : false
    check_return(barr, caught)
  end

  facts("Check Return Types: False Negatives") do
    foo(x::Any) = isprime(x) ? x : false
    check_return(foo, notcaught)
  end

  exitstatus()
end
