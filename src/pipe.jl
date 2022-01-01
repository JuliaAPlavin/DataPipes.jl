macro asis(expr)
    data = gensym("data")
    expr_replaced = replace_in_pipeexpr(expr, Dict(:↑ => data))
    if expr_replaced != expr
        :($(esc(data)) -> $(esc(expr_replaced)))
    else
        esc(expr)
    end
end


macro pipe(block)
    pipe_macro(block)
end

macro pipe(exprs...)
    pipe_macro(exprs)
end

Base.@kwdef mutable struct State
    prev::Symbol
    exports::Vector{Symbol}
end

function pipe_macro(block)
    exprs = get_exprs(block)
    exprs = filter(e -> !(e isa LineNumberNode), exprs)
    exprs_processed = []
    state = nothing
    for e in exprs
        ep, state = process_pipe_step(e, state)
        push!(exprs_processed, ep)
    end
    quote
        ($(esc.([state.exports..., state.prev])...),) = let
            $(exprs_processed...)
            ($(esc.([state.exports..., state.prev])...),)
        end
        $(esc(state.prev))
    end
end

get_exprs(block) = [block]
get_exprs(block::Tuple) = block
get_exprs(block::Expr) = if block.head == :block
    # block like `begin ... end`
    block.args
elseif block.head == :call && block.args[1] == :(|>)
    # piped functions like `a |> f1 |> f2`
    exprs = []
    while block isa Expr && block.head == :call && block.args[1] == :(|>)
        pushfirst!(exprs, block.args[3])
        block = block.args[2]
    end
    pushfirst!(exprs, block)
    exprs
elseif block.head == :call
    # single function call
    [block]
else
    # everything else
    [block]
end


function process_pipe_step(e, state)
    e, exports = process_exports(e)
    assign_lhs, e = split_assignment(e)
    next = gensym("res")
    e = isnothing(state) ? e : transform_pipe_step(e; state.prev, next)
    e = if isnothing(assign_lhs)
        :($(esc(next)) = $(esc(e)))
    else
        :($(esc(next)) = $(esc(assign_lhs)) = $(esc(e)))
    end
    state = something(state, State(:_, []))
    state.prev = next
    append!(state.exports, exports)
    return e, state
end

function transform_pipe_step(e::Symbol; prev::Symbol, next::Symbol)
    e == :↑ ? prev : :($(e)($(prev)))
end
# function transform_pipe_step(e::Union{String, Number}, state::State)
#     next = gensym("res")
#     @set! prev = next
#     e
# end
function transform_pipe_step(e::Expr; prev::Symbol, next::Symbol)
    return if e.head == :call
        fname = e.args[1]
        body = pipe_process_exprfunc(Val(func_name(fname)), fname, e.args[2:end], prev)
        e = body
        e = replace_in_pipeexpr(e, Dict(:↑ => prev))
    elseif e.head == :do
        @assert length(e.args) == 2
        @assert e.args[1].head == :call
        fname = e.args[1].args[1]
        @assert e.args[2].head == :(->)
        body = e.args[2]
        body = pipe_process_exprfunc(Val(func_name(fname)), fname, [body], prev)
        e = body
        e = replace_in_pipeexpr(e, Dict(:↑ => prev))
    else
        e_replaced = replace_in_pipeexpr(e, Dict(:↑ => prev))
        if e_replaced != e
            e_replaced
        else
            e
        end
    end
end

process_exports(x) = x, []
function process_exports(expr::Expr)
    exports = []
    proc_f(x) = x
    proc_f(e::Expr) = if e.head == :macrocall && e.args[1] == Symbol("@export")
        msg = "Wrong @export format"
        @assert length(e.args) == 3  msg
        @assert e.args[2] isa LineNumberNode  msg
        @assert e.args[3] isa Expr  msg
        @assert e.args[3].head == :(=)  msg
        if e.args[3].args[1] isa Symbol
            # single assingment: a = ...
            push!(exports, e.args[3].args[1])
        else
            # multiple assignment: a, b, c = ...
            @assert e.args[3].args[1] isa Expr  msg
            @assert e.args[3].args[1].head == :tuple  msg
            @assert all(a -> a isa Symbol, e.args[3].args[1].args)  msg
            append!(exports, e.args[3].args[1].args)
        end
        return e.args[3]
    else
        return e
    end
    expr = postwalk(proc_f, expr)
    expr, exports
end

split_assignment(x) = nothing, x
function split_assignment(expr::Expr)
    if expr.head == :(=)
        @assert length(expr.args) == 2  "Wrong assingment format"
        return expr.args[1], expr.args[2]
    else
        return nothing, expr
    end
end

func_name(e::Symbol) = e
func_name(e::Expr) = let
    @assert e.head == :.
    @assert length(e.args) == 2
    return e.args[2].value
end

function pipe_process_exprfunc(func_short::Val, func_full, args, data)
    args_processed = map(enumerate(args)) do (i, arg)
        if arg isa Expr && arg.head == :kw
            @assert length(arg.args) == 2
            key = arg.args[1]
            value = arg.args[2]
            nargs = func_nargs(func_short, key)
            Expr(:kw, key, func_or_body_to_func(value, nargs, data))
        else
            nargs = func_nargs(func_short, Val(i))
            func_or_body_to_func(arg, nargs, data)
        end
    end
    if need_append_data_arg(args)
        :( $(func_full)($(args_processed...), $data) )
    else
        :( $(func_full)($(args_processed...)) )
    end
end

need_append_data_arg(args) = !any(args) do arg
    occursin_expr(ee -> is_pipecall(ee) ? StopWalk(ee) : ee == :↑, arg)
end

func_nargs(func, argix) = 1
func_nargs(func::Val{:mapmany}, argix::Val{2}) = 2
func_nargs(func::Val{:product}, argix::Val{1}) = 2
func_nargs(func::Union{Val{:innerjoin}, Val{:leftgroupjoin}}, argix::Val{3}) = 2
func_nargs(func::Union{Val{:innerjoin}, Val{:leftgroupjoin}}, argix::Val{4}) = 2

is_pipecall(e) = false
is_pipecall(e::Expr) = e.head == :macrocall && e.args[1] ∈ (Symbol("@pipe"), Symbol("@p"))

function func_or_body_to_func(e, nargs::Int, data::Symbol)
    args = [gensym("x_$i") for i in 1:nargs]
    syms_replacemap = Dict(Symbol("_"^i) => args[i] for i in 1:nargs)
    prewalk(e) do ee
        is_pipecall(ee) && return StopWalk(ee)
        if ee isa Symbol && all(c == '_' for c in string(ee)) && !haskey(syms_replacemap, ee)
            throw("Unknown all-underscore variable `$(ee)` in pipe. Too many underscores?")
        end
    end
    e_replaced = replace_in_pipeexpr(e, syms_replacemap)
    if e_replaced != e
        if e_replaced isa Expr && e_replaced.head == :(->)
            # already a function definition
            e_replaced
        else
            # just function body, need to turn into definition
            :(($(args...),) -> $e_replaced)
        end
    else
        e
    end
end

replace_in_pipeexpr(expr, syms_replacemap) = prewalk(expr) do ee
    is_pipecall(ee) && return StopWalk(replace_within_inner_pipe(ee, syms_replacemap))
    haskey(syms_replacemap, ee) && return syms_replacemap[ee]
    return ee
end

replace_within_inner_pipe(expr, syms_replacemap) = prewalk(expr) do e
    e isa Symbol || return e
    m = match(r"^(.+)1$", string(e))
    if m != nothing && haskey(syms_replacemap, Symbol(m[1]))
        return syms_replacemap[Symbol(m[1])]
    end
    m = match(r"^(.+)(\d+)$", string(e))
    if m != nothing && haskey(syms_replacemap, Symbol(m[1]))
        return Symbol("$(m[1])$(parse(Int, m[2]) - 1)")
    end
    return e
end
