macro pipe(block) pipe_macro(block) end
macro pipe(exprs...) pipe_macro(exprs) end
macro pipefunc(block) pipefunc_macro(block) end
macro pipefunc(exprs...) pipefunc_macro(exprs) end

Base.@kwdef mutable struct State
    prev::Union{Symbol, Nothing}
    exports::Vector{Symbol}
    assigns::Vector{Symbol}
end

function pipefunc_macro(block)
    arg = gensym("pipefuncarg")
    exprs_processed, state = process_block(block, arg)
    :( $(esc(arg)) -> $(exprs_processed...) )
end

function pipe_macro(block)
    exprs_processed, state = process_block(block, nothing)
    quote
        ($(esc.([state.exports..., state.prev])...),) = let ($((state.assigns)...))
            $(exprs_processed...)
            ($(esc.([state.exports..., state.prev])...),)
        end
        $(esc(state.prev))
    end
end

function process_block(block, initial_arg)
    exprs = get_exprs(block)
    exprs_processed = []
    state = State(initial_arg, [], [])
    for e in exprs
        ep, state = process_pipe_step(e, state)
        push!(exprs_processed, ep)
    end
    return exprs_processed, state
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


process_pipe_step(e::LineNumberNode, state) = e, state
function process_pipe_step(e, state)
    e, exports = process_exports(e)
    e, is_aside = search_macro_flag(e, Symbol("@aside"))
    assign_lhs, e, assigns = split_assignment(e)
    next = gensym("res")
    e, keep_asis = search_macro_flag(e, Symbol("@asis"))
    e, no_add_prev = search_macro_flag(e, Symbol("@_"))
    if !keep_asis
        e = transform_pipe_step(e, no_add_prev ? nothing : state.prev)
        e = replace_in_pipeexpr(e, Dict(:↑ => state.prev))
    end
    e = if isnothing(assign_lhs)
        :($(esc(next)) = $(esc(e)))
    else
        :($(esc(next)) = $(esc(assign_lhs)) = $(esc(e)))
    end
    if !is_aside
        state.prev = next
    end
    append!(state.exports, exports)
    append!(state.assigns, assigns)
    return e, state
end

transform_pipe_step(e, prev) = e

transform_pipe_step(e::Symbol, prev::Nothing) = e
transform_pipe_step(e::Symbol, prev::Symbol) = e == :↑ ? prev : :($(e)($(prev)))

function transform_pipe_step(e::Expr, prev::Union{Symbol, Nothing})
    if e.head == :call
        # regular function call: map(a, b)
        fname = e.args[1]
        args = e.args[2:end]
        pipe_process_exprfunc(fname, args, prev)
    elseif e.head == :do
        # do-call: map(a) do ... end
        @assert length(e.args) == 2  # TODO: any issues with supporting more args?
        @assert e.args[1].head == :call
        @assert e.args[2].head == :(->)
        fname = e.args[1].args[1]
        args = [e.args[2:end]..., e.args[1].args[2:end]...]  # do-arg first, then all args from within the call
        pipe_process_exprfunc(fname, args, prev)
    else
        # anything else
        # e.g., a[b], macro call, what else?
        e
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
        append!(exports, assigned_names(e.args[3].args[1]))
        return e.args[3]
    else
        return e
    end
    expr = postwalk(proc_f, expr)
    expr, exports
end

search_macro_flag(x, macroname::Symbol) = x, false
function search_macro_flag(expr::Expr, macroname::Symbol)
    found = false
    proc_f(x) = x
    proc_f(e::Expr) = if e.head == :macrocall && e.args[1] == macroname
        msg = "Wrong $macroname format"
        @assert length(e.args) == 3  msg
        @assert e.args[2] isa LineNumberNode  msg
        found = true
        return e.args[3]
    else
        return e
    end
    expr = prewalk(expr) do e
        is_pipecall(e) && return StopWalk(e)
        return proc_f(e)
    end
    expr, found
end

split_assignment(x) = nothing, x, []
function split_assignment(expr::Expr)
    if expr.head == :(=)
        @assert length(expr.args) == 2  "Wrong assingment format"
        return expr.args[1], expr.args[2], assigned_names(expr.args[1])
    else
        return nothing, expr, []
    end
end

# single assingment: a = ...
assigned_names(lhs::Symbol) = [lhs]
# multiple assignment: a, b, c = ...
assigned_names(lhs::Expr) = (
    msg = "Wrong assingment format";
    @assert lhs.head == :tuple  msg;
    @assert all(a -> a isa Symbol, lhs.args)  msg;
    lhs.args
)

# un-qualify name, e.g. :map -> :map, :(Base.map) -> :map
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

function pipe_process_exprfunc(func_fullname, args, prev::Union{Symbol, Nothing})
    args_processed = map(enumerate(args)) do (i, arg)
        transform_arg(arg, func_fullname, i)
    end
    if !isnothing(prev) && need_append_data_arg(args)
        name = string(unqualified_name(func_fullname))
        isletter(name[1]) || @warn "Pipeline step top-level function is an operator. An argument with the previous step results is still appended." func=name args
        :( $(func_fullname)($(args_processed...), $prev) )
    else
        :( $(func_fullname)($(args_processed...)) )
    end
end

function transform_arg(arg::Expr, func_fullname, i::Union{Int, Nothing})
    if arg isa Expr && arg.head == :parameters
        # arg is multiple kwargs, with preceding ';'
        Expr(arg.head, map(arg.args) do arg
            transform_arg(arg, func_fullname, nothing)
        end...)
    elseif arg.head == :kw
        # is a kwarg
        @assert length(arg.args) == 2
        key, value = arg.args
        nargs = func_nargs(func_fullname, key)
        Expr(:kw, key, func_or_body_to_func(value, nargs))
    else
        nargs = func_nargs(func_fullname, i)
        func_or_body_to_func(arg, nargs)
    end
end

function transform_arg(arg, func_fullname, i::Union{Int, Nothing})
    nargs = func_nargs(func_fullname, i)
    func_or_body_to_func(arg, nargs)
end

# check if therea re no "↑"s in args
need_append_data_arg(args) = !any(args) do arg
    occursin_expr(ee -> is_pipecall(ee) ? StopWalk(ee) : ee == :↑, arg)
end

# expected number of arguments in argix'th argument of func if this arg is a function itself
# this sets the minimum, additional underscores always get converted to more arguments
func_nargs(func, argix) = func_nargs(Val(unqualified_name(func)), argix)
func_nargs(func::Val, argix::Union{Int, Symbol, Nothing}) = func_nargs(func, Val(argix))
func_nargs(func::Val, argix::Val) = 1  # so that _ is replaced everywhere
func_nargs(func::Val{:mapmany}, argix::Val{2}) = 2
func_nargs(func::Val{:product}, argix::Val{1}) = 2
func_nargs(func::Union{Val{:innerjoin}, Val{:leftgroupjoin}}, argix::Val{3}) = 2
func_nargs(func::Union{Val{:innerjoin}, Val{:leftgroupjoin}}, argix::Val{4}) = 2

is_pipecall(e) = false
is_pipecall(e::Expr) = e.head == :macrocall && e.args[1] ∈ (Symbol("@pipe"), Symbol("@p"), Symbol("@pipefunc"), Symbol("@f"))

# if contains "_"-like placeholder: transform to function
# otherwise keep as-is
function func_or_body_to_func(e, nargs::Int)
    prewalk(e) do ee
        is_pipecall(ee) && return StopWalk(ee)
        if ee isa Symbol && all(c == '_' for c in string(ee))
            # all-underscore variable found
            nargs = max(nargs, length(string(ee)))
        end
        return ee
    end

    args = [gensym("x_$i") for i in 1:nargs]
    syms_replacemap = Dict(Symbol("_"^i) => args[i] for i in 1:nargs)
    
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

# replace symbols in expr
# nested @pipes: replace <symbol>1 as if it was <symbol> outside of nested pipe
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
