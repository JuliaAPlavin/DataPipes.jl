val(::Val{V}) where {V} = V


# taken from MacroTools.jl package
walk(x, inner, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))
walk(x::Tuple, inner, outer) = outer(map(inner, x))


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
