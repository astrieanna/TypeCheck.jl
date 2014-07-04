# A Collection of static analysis functions.
#
# These functions implement some static type-checking of Julia programs.
# There are also other type-related functions to allow human-readable output
# of things like the types of function-local variables.
module TypeCheck
export checkreturntypes, checklooptypes, checkmethodcalls,
  methodswithdescendants, checkmissingexports
import Base.Callable

## Modifying functions from Base

# Base.code_typed requires a function and tuple of argument types.
# It can be more convenient to pass in a Function or Method.
# A method specifies the same information as a Function + argument types,
# so the implementation is obvious.
# For a Function, code_typed should return a list of Expr, on per method.

# Return the type-inferred AST for each method of a generic Function.
function Base.code_typed(f::Callable)
  isa(f,DataType) && f.abstract && return Expr[] # abstract types have no constructors
  Expr[code_typed(m) for m in f.env]
end

# Return the type-inferred AST for one Method (of a generic Function)
function Base.code_typed(m::Method)
 linfo = m.func.code
 (tree,ty) = Base.typeinf(linfo,m.sig,())
 if !isa(tree,Expr)
     ccall(:jl_uncompress_ast, Any, (Any,Any), linfo, tree)
 else
    tree
 end
end

# The whos function takes a namespace (a Module or the current one) and
# prints out the bound names and types (variables, types, functions, consts).
# I'm adding a version to print out function-local variables.
# Specify a method via a Method, unction, or Function+argument-type-tuple.
function Base.whos(f,args...)
  for e in code_typed(f,args...)
    display(MethodSignature(e))
    for x in sort(e.args[2][2];by=x->x[1])
      println("\t",x[1],"\t",x[2])
    end
    println("")
  end
end

## Basic Operations on Function Exprs

# Return the inferred return of type of an Expr representing a Method
returntype(e::Expr) =  e.args[3].typ

# Return the body of a Method.
# Takes an Expr representing a Method, returns Vector{Expr}.
body(e::Expr) = e.args[3].args

# Return all of the return statements in the body of a Method
# Takes an Expr representing a Method, return Vector{Expr}
returns(e::Expr) = filter(x-> typeof(x) == Expr && x.head==:return,body(e))

# Returns all function calls contained in return statements in the body of a Method.
# Takes an Expr representing a Method, returns Vector{Expr}
function extractcallsfromreturns(e::Expr)
  rs = returns(e)
  rs_with_calls = filter(x->typeof(x.args[1]) == Expr && x.args[1].head == :call,rs)
  Expr[expr.args[1] for expr in rs_with_calls]
end

# A type that covers both Types and TypeVars
AType = Union(Type,TypeVar)

# Returns the type of each argument in a Method's signature
# Takes an Expr representing a Method, returns Vector{AType}
function argumenttypes(e::Expr)
  argnames = Symbol[typeof(x) == Symbol ? x : x.args[1] for x in e.args[1]]
  argtuples = filter(x->x[1] in argnames, e.args[2][2]) #only arguments, no local vars
  AType[t[2] for t in argtuples]
end

# Returns true if the Expr is a :call to a TopNode
# Takes an Expr (or Any) and returns a Bool
istop(e) = Base.is_expr(e,:call) && typeof(e.args[1]) == TopNode

# Returns the return type of an Expr (:call, :call1, :new)
# Takes an Expr(call) and the Expr representing the method it occurs in
# Returns an AType
function returntype(e::Expr,context::Expr) #must be :call,:new,:call1
  if Base.is_expr(e,:new); return e.typ; end
  if Base.is_expr(e,:call1) && isa(e.args[1], TopNode); return e.typ; end
  if !Base.is_expr(e,:call); error("Expected :call Expr"); end

  if istop(e)
    return e.typ
  end

  callee = e.args[1]
  if istop(callee)
    return returntype(callee,context)
  elseif isa(callee,SymbolNode) # only seen (func::F), so non-generic function
    return Any
  elseif is(callee,Symbol)
    if e.typ != Any || any([isa(x,LambdaStaticData) for x in e.args[2:end]])
      return e.typ
    end

    if isdefined(Base,callee)
      f = eval(Base,callee)
      if !isa(f,Callable) || !isgeneric(f)
        return e.typ
      end
      fargtypes = tuple([argumenttype(ea,context) for ea in e.args[2:end]])
      return Union([returntype(ef) for ef in code_typed(f,fargtypes)]...)
    else
      return @show e.typ
    end
  end

  return e.typ
end

# Returns the type of an Expr
# Takes an Expr and the Expr representing a Method it occurs in
function argumenttype(e::Expr,context::Expr)
 if Base.is_expr(e,:call) || Base.is_expr(e,:new) || Base.is_expr(e,:call1)
   return returntype(e,context)
 end

 @show e
 return Any
end

# Returns the type of a Symbol used as an argument to a function call
# Takes a Symbol and an Expr representing a Method it occurs in
function argumenttype(s::Symbol,e::Expr)
  vartypes = [x[1] => x[2] for x in e.args[2][2]]
  s in vartypes ? (vartypes[@show s]) : Any
end

# as above, but for different call argument types
argumenttype(s::SymbolNode,e::Expr) = s.typ
argumenttype(t::TopNode,e::Expr) = Any
argumenttype(l::LambdaStaticData,e::Expr) = Function
argumenttype(q::QuoteNode,e::Expr) = argumenttype(q.value,e)

# as above, but for various literal values
argumenttype(n::Number,e::Expr) = typeof(n)
argumenttype(c::Char,e::Expr) = typeof(c)
argumenttype(s::String,e::Expr) = typeof(s)
argumenttype(i,e::Expr) = typeof(i) #catch all, hopefully for more literals

# Make Types Iterable
# start, next, and done are the functions for-loops use to iterate.
# This defines iterating over a DataType to mean iterating over its descendants
# (breadth-first-search ordering)
Base.start(t::DataType) = [t]
function Base.next(t::DataType,arr::Vector{DataType})
  c = pop!(arr)
  append!(arr,[x for x in subtypes(c)])
  (c,arr)
end
Base.done(t::DataType,arr::Vector{DataType}) = length(arr) == 0

# Returns a list of Function names to implementation percentage.
# By considering all the descendents of the provided type,
# this function collects a list of functions implemented by at least one
# considered type and calculates what percentage of the considered types
# implements each function.
#
# Takes a DataType and returns a Vector{(Symbol,Float64)}
# Keyword args:
#   onlyleaves: If this is true, only concrete types are considered;
#     if this is false, all descendent types are considered.
#     (defaults to false)
#   lim: The maximum length of the returned list. The lim functions with
#     the highest implementation rate will be returned.
function methodswithdescendants(t::DataType;onlyleaves::Bool=false,lim::Int=10)
  d = Dict{Symbol,Int}()
  count = 0
  for s in t
    if !onlyleaves || (onlyleaves && isleaftype(s))
      count += 1
      fs = Set{Symbol}()
      for m in methodswith(s)
        push!(fs,m.func.code.name)
      end
      for sym in fs
        d[sym] = get(d,sym,0) + 1
      end
    end
  end
  l = [(k,v/count) for (k,v) in d]
  sort!(l,by=(x->x[2]),rev=true)
  l[1:min(lim,end)]
end

# Run a function on each generic function of a Module.
# Takes a Module, returns nothing.
# The output of each run of the test function will be displayed.
function checkallmodule(m::Module;test=checkreturntypes,kwargs...)
  score = 0
  for n in names(m,true,false)
    if isdefined(m,n)
      f = getfield(m,n)
      if isgeneric(f) && isa(f,Callable)
        fm = test(f;mod=m,kwargs...)
        score += length(fm.methods)
        display(fm)
      end
    end
  end
  println("The total number of failed methods in $m is $score")
end

# Use checkallmodule to implement the Module version of other checks
checkreturntypes(m::Module;kwargs...) = checkallmodule(m;test=checkreturntypes,kwargs...)
checklooptypes(m::Module) = checkallmodule(m;test=checklooptypes)
checkmethodcalls(m::Module) = checkallmodule(m;test=checkmethodcalls)

## Checking that return values are base only on input *types*, not values.

type MethodSignature
  typs::Vector{AType}
  returntype::Union(Type,TypeVar) # v0.2 has TypeVars as returntypes; v0.3 does not
end
MethodSignature(e::Expr) = MethodSignature(argumenttypes(e),returntype(e))
function Base.writemime(io, ::MIME"text/plain", x::MethodSignature)
  println(io,"(",join([string(t) for t in x.typs],","),")::",x.returntype)
end

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

# given a function, run checkreturntypes on each method
function checkreturntypes(f::Callable;kwargs...)
  results = MethodSignature[]
  for e in code_typed(f)
    (ms,b) = checkreturntype(e;kwargs...)
    if b push!(results,ms) end
  end
  FunctionSignature(results,f.env.name)
end

# given an Expr representing a Method,
# determine whether its return type is based
# only on the arugment types or whether it is
# also influenced by argument values
# (the Method fails the check if the return type depends on values)
function checkreturntype(e::Expr;kwargs...)
  (typ,b) = isreturnbasedonvalues(e;kwargs...)
  (MethodSignature(argumenttypes(e),typ),b)
end

# Determine whether this method's return type might change based on input values rather than input types
function isreturnbasedonvalues(e::Expr;mod=Base)
  rt = returntype(e)
  ts = argumenttypes(e)
  if isleaftype(rt) || rt == None return (rt,false) end

  for t in ts
    if !isleaftype(t)
      return (rt,false)
    end
  end

  cs = [returntype(c,e) for c in extractcallsfromreturns(e)]
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

# for a given Function, run checklooptypes on each Method
function checklooptypes(f::Callable;kwargs...)
  lrs = LoopResult[]
  for e in code_typed(f)
    lr = checklooptypes(e)
    if length(lr.lines) > 0 push!(lrs,lr) end
  end
  LoopResults(f.env.name,lrs)
end

# for an Expr representing a Method,
# check that the type of each variable used in a loop
# has a concrete type
checklooptypes(e::Expr;kwargs...) = LoopResult(MethodSignature(e),loosetypes(loopcontents(e)))

# This is a function for trying to detect loops in the body of a Method
# Returns lines that are inside one or more loops
function loopcontents(e::Expr)
  b = body(e)
  loops = Int[]
  nesting = 0
  lines = {}
  for i in 1:length(b)
    if typeof(b[i]) == LabelNode
      l = b[i].label
      jumpback = findnext(
        x-> (typeof(x) == GotoNode && x.label == l) || (Base.is_expr(x,:gotoifnot) && x.args[end] == l),
        b, i)
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

# given `lr`, a Vector of expressions (Expr + literals, etc)
# try to find all occurances of a variables in `lr`
# and determine their types
# `method` is only used as part of constructing the return type
function loosetypes(lr::Vector)
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
  return lines
end

## Check method calls

type CallSignature
  name::Symbol
  argumenttypes::Vector{AType}
end
function Base.writemime(io, ::MIME"text/plain", x::CallSignature)
  println(io,string(x.name),"(",join([string(t) for t in x.argumenttypes],","),")")
end

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

# given a Function, run `checkmethodcalls` on each Method
# and collect the results into a FunctionCalls
function checkmethodcalls(f::Callable;kwargs...)
  calls = MethodCalls[]
  for m in f.env
    e = code_typed(m)
    mc = checkmethodcalls(e,m;kwargs...)
    if !isempty(mc.calls)
      push!(calls, mc)
    end
  end
  FunctionCalls(f.env.name,calls)
end

# given an Expr representing a Method,
# and the Method it represents,
# check the Method body for calls to non-existant Methods
function checkmethodcalls(e::Expr,m::Method;kwargs...)
  if Base.arg_decl_parts(m)[3] == symbol("deprecated.jl")
    CallSignature[]
  end
  nomethoderrors(e,methodcalls(e);kwargs...)
end

# Find any methods that match the given CallSignature
function hasmatches(mod::Module,cs::CallSignature)
  if isdefined(mod,cs.name)
    f = eval(mod,cs.name)
    if isgeneric(f)
      opts = methods(f,tuple(cs.argumenttypes...))
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
function nomethoderrors(e::Expr,cs::Vector{CallSignature};mod=Base)
  output = CallSignature[]
  for callsig in cs
    if !hasmatches(mod,callsig)
      push!(output,callsig)
    end
  end
  MethodCalls(MethodSignature(e),output)
end

# Look through and Expr for `:call`s
methodcalls(m::Expr) = methodcalls(body(m), m, CallSignature[])
function methodcalls(e::Expr, m::Expr, lines::Vector{CallSignature})
  if e.head === :call || e.head === :call1
    if typeof(e.args[1]) == Symbol
      push!(lines,CallSignature(e.args[1], [argumenttype(e1,m) for e1 in e.args[2:end]]))
    end
  end
  methodcalls(e.args, m, lines)
  lines
end
function methodcalls(e::Vector, m::Expr, lines::Vector{CallSignature})
  for a in e
      if isa(a,Expr)
          methodcalls(a::Expr, m, lines)
      end
  end
  lines
end

# Return a list of all variables used on the left-hand-side of assignment (=)
#
# Arguments:
#   e: an Expr representing a Method, as from code_typed
#
# Returns:
#   a Set{Symbol}, where each element appears on the lhs of an assignment in e.
#
function find_lhs_variables(e::Expr)
  output = Set{Symbol}()
  for ex in body(e)
   isa(ex,Expr) && ex.head == symbol("=") && push!(output,ex.args[1])
  end
  return output
end

# Given an Expression, finds variables used in it (on right-hand-side)
#
# Arguments: e: an Expr
#
# Returns: a Set{Symbol}, where each e is used in a rhs expression in e
#
function find_rhs_variables(e::Expr)
  output = Set{Symbol}()

  if e.head == :lambda
    for ex in body(e)
      union!(output,find_rhs_variables(ex))
    end
  elseif e.head == :(=)
    for ex in e.args[2:end]  # skip lhs
      union!(output,find_rhs_variables(ex))
    end
  elseif e.head == :return
    output = find_rhs_variables(e.args[1])
  elseif e.head == :call
    start = 2  # skip function name
    e.args[1] == TopNode(:box) && (start = 3)  # skip type name
    for ex in e.args[start:end]
      union!(output,find_rhs_variables(ex))
    end
  elseif e.head == :if
   for ex in e.args # want to check condition, too
     union!(output,find_rhs_variables(ex))
   end
  elseif e.head == :(::)
    output = find_rhs_variables(e.args[1])
  end

  return output
end

# Recursive Base Cases, to simplify control flow in the Expr version
find_rhs_variables(a) = Set{Symbol}()  # unhandled, should be an immediate value, like an Int.
find_rhs_variables(s::Symbol) = Set{Symbol}([s])
find_rhs_variables(s::SymbolNode) = Set{Symbol}([s.name])

function unused_locals(e::Expr)
  lhs = find_lhs_variables(e)
  rhs = find_rhs_variables(e)
  setdiff(lhs,rhs)
end

check_locals(f::Callable) = all([check_locals(e) for e in code_typed(f)])
check_locals(e::Expr) = isempty(unused_locals(e))

checkmissingexports(m::Module) = isempty(find_missing_exports(m))
function find_missing_exports(m::Module=Base, missing::Vector{(Module,Symbol)}=(Module,Symbol)[])
  for n in names(m,true,false)
    if isdefined(m,n)
      f = getfield(m,n)
      if isa(f,Module) && f !== m
        find_missing_exports(f, missing)
      end
    else
      push!(missing,(m,n))
    end
  end
  missing
end

typealias InterfaceDict Dict{DataType, Set{Symbol}}
function extract_interfaces(m::Module=Base, ifaces::InterfaceDict=InterfaceDict())
  for n in names(m)
    if isdefined(m,n)
      f = getfield(m,n)
      if (isa(f,Callable) && isgeneric(f)) || (isa(f,Module) && f !== m)
        extract_interfaces(f, ifaces)
      end
    end
  end
  ifaces
end
extract_interfaces(f::Callable) = extract_interfaces(f, InterfaceDict())
extract_interfaces(f::Callable, ifaces::InterfaceDict) = extract_interfaces(code_typed(f), ifaces)
function extract_interfaces(meths::Vector{Expr}, ifaces::InterfaceDict)
  for m in meths
    sigs = methodcalls(m)
    for s in sigs
      for t in s.argumenttypes
        add_iface(t, s.name, ifaces)
      end
    end
  end
  ifaces
end

add_iface(t::TypeVar, f::Symbol, ifaces::InterfaceDict) = add_iface(t.ub, f, ifaces)
add_iface(t::TypeConstructor, f::Symbol, ifaces::InterfaceDict) = add_iface(t.body, f, ifaces)
function add_iface(t::UnionType, f::Symbol, ifaces::InterfaceDict)
  for t in t.types
    add_iface(t, f, ifaces)
  end
end
add_iface(t::Tuple, f::Symbol, ifaces::InterfaceDict) = nothing #todo
function add_iface(t::DataType, f::Symbol, ifaces::InterfaceDict)
  t.abstract || return
  if !(t in keys(ifaces))
    ifaces[t] = fn = Set{Symbol}()
  else
    fn = ifaces[t]
  end
  push!(fn, f)
  nothing
end
# todo: second pass to reduce {Real=>:abs, Integer=>:abs} to {Real=>abs} in ifaces

end  #end module
