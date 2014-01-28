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

  facts("Check Return Types: True Positives") do
    barr(x::Int) = isprime(x) ? x : false
    @fact length(code_typed(barr)) => 1
    @fact TypeCheck.check_return_value(code_typed(barr)[1]) => x -> x[2] == true
  end

  facts("Check Return Types: False Negatives") do
    foo(x::Any) = isprime(x) ? x : false
    @fact length(code_typed(foo)) => 1
    @fact TypeCheck.check_return_value(code_typed(foo)[1]) => x -> x[2] == false
  end

  exitstatus()
end
