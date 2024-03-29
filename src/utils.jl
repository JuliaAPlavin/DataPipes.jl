# taken from MacroTools.jl package
walk(x, inner, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))
walk(x::Union{Tuple,AbstractVector}, inner, outer) = outer(map(inner, x))


abstract type WalkModifier end

struct StopWalk <: WalkModifier
    value
end

struct ContinueWalk <: WalkModifier
    value
end

postwalk(f, x) = walk(x, x -> postwalk(f, x), f)
function prewalk(f, x)
    x_ = f(x)
    x_ isa StopWalk ? x_.value :
    x_ isa ContinueWalk ? prewalk(f, x_.value) :
    walk(x_, x -> prewalk(f, x), identity)
end

occursin_expr(needle::Function, haystack) = count_expr(needle, haystack) > 0

function count_expr(needle::Function, haystack)
    cnt = 0
    prewalk(haystack) do ee
        n = needle(ee)
        n isa WalkModifier && return n
        cnt += n::Bool
        ee
    end
    return cnt
end


is_kwexpr(e) = false
is_kwexpr(e::Expr) =
    e.head == :kw ||  # semicolon kwargs such as (; a=1)
    e.head == :(=) && e.args[1] isa Symbol  # no-semicolon kwargs such as (a=1,)
" Wrap first argument of a kwexpr into a StopWalk so that it's not processed in the walk afterwards. "
function kwexpr_skipfirst(e::Expr)
    @assert is_kwexpr(e)
    Expr(e.head, StopWalk(e.args[1]), e.args[2:end]...)
end

is_lambda_function(e) = false
is_lambda_function(e::Expr) = e.head == :(->) || e.head == :function
lambda_function_args(e::Expr) = if e.args[1] isa Symbol
    (e.args[1],)
else
    @assert e.args[1].head == :tuple
    Tuple(e.args[1].args)
end
lambda_function_body(e::Expr) = e.args[2]


split_assignment(x) = nothing, x, []
function split_assignment(expr::Expr)
    if expr.head == :(=)
        @assert length(expr.args) == 2  "Wrong assignment format"
        return expr.args[1], expr.args[2], assigned_names(expr.args[1])
    else
        return nothing, expr, []
    end
end

# single assignment: a = ...
assigned_names(lhs::Symbol) = [lhs]
# multiple assignment: a, b, c = ...
assigned_names(lhs::Expr) = (
    msg = "Wrong assignment format";
    @assert lhs.head == :tuple  msg;
    @assert all(a -> a isa Symbol, lhs.args)  msg;
    lhs.args
)

is_qualified_name(e::Expr) = e.head == :(.) && length(e.args) == 2 && e.args[2] isa QuoteNode

# un-qualify name, e.g. :map -> :map, :(Base.map) -> :map
unqualified_name(e) = Symbol(e)  # eg functions themselves
unqualified_name(e::Symbol) = e
unqualified_name(e::Expr) = let
    if e.head == :.
        # qualified function name, eg :(Base.map)
        @assert length(e.args) == 2
        return e.args[2].value
    else
        # any other expression: cannot "unqualify"
        nothing
    end
end


modify_argbody(f, arg) = f(arg)
modify_argbody(f, arg::Expr) =
    if arg.head == :parameters
        # multiple kwargs, with preceding ';'
        Expr(arg.head, map(arg.args) do arg
            modify_argbody(f, arg)
        end...)
    elseif arg.head == :kw
        # single kwarg
        @assert length(arg.args) == 2
        Expr(:kw, arg.args[1], f(arg.args[2]))
    else
        # positional argument
        f(arg)
    end


# macro for Symbol
macro S_str(str)
    :(Symbol($(esc(str))))
end


# hack? see https://github.com/JuliaWeb/HTTP.jl/pull/981/files
macro remove_linenums!(expr)
    return esc(Base.remove_linenums!(expr))
end


filtermap(f, A) = map(something, filter(!isnothing, map(f, A)))
