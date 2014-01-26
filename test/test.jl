module TestTypeCheck
  using TypeCheck, FactCheck
  
  facts("Check Return Types") do
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

  exitstatus()
end
