val(::Val{V}) where {V} = V


# taken from MacroTools.jl package
walk(x, inner, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))
walk(x::Tuple, inner, outer) = outer(map(inner, x))


struct StopWalk
    value
end

postwalk(f, x) = walk(x, x -> postwalk(f, x), f)
prewalk(f, x)  = (x_ = f(x); x_ isa StopWalk ? x_.value : walk(x_, x -> prewalk(f, x), identity))

occursin_expr(needle::Function, haystack) = count_expr(needle, haystack) > 0

function count_expr(needle::Function, haystack)
    cnt = 0
    prewalk(haystack) do ee
        n = needle(ee)
        if n isa StopWalk
            n
        elseif n
            cnt += 1
            ee
        else
            @assert !n
            ee
        end
    end
    return cnt
end
