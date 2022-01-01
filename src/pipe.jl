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
    :( $(arg) -> $(exprs_processed...) ) |> esc
end

function pipe_macro(block)
    exprs_processed, state = process_block(block, nothing)
    quote
        ($([state.exports..., state.prev]...),) = let ($((state.assigns)...))
            $(exprs_processed...)
            ($([state.exports..., state.prev]...),)
        end
        $(state.prev)
    end |> esc
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
        e = replace_in_pipeexpr(e, Dict(PREV_PLACEHOLDER => state.prev))
    end
    e = if isnothing(assign_lhs)
        :($(next) = $(e))
    else
        :($(next) = $(assign_lhs) = $(e))
    end
    if !is_aside
        state.prev = next
    end
    append!(state.exports, exports)
    append!(state.assigns, assigns)
    return e, state
end

# symbol as the first pipeline step: keep as-is
transform_pipe_step(e::Symbol, prev::Nothing) = e
# symbol as latter pipeline steps: generally represents a function call
transform_pipe_step(e::Symbol, prev::Symbol) = e == PREV_PLACEHOLDER ? prev : :($(e)($(prev)))
function transform_pipe_step(e, prev::Union{Symbol, Nothing})
    fcall = dissect_function_call(e)
    if !isnothing(fcall)
        args_processed = transform_args(fcall.funcname, fcall.args)
        args_processed = add_prev_arg_if_needed(fcall.funcname, args_processed, prev)
        :( $(fcall.funcname)($(args_processed...)) )
    else
        # pipe step not a function call: keep it as-is
        e
    end
end

dissect_function_call(e) = nothing
dissect_function_call(e::Symbol) = @assert false
function dissect_function_call(e::Expr)
    if e.head == :call
        # regular function call: map(a, b)
        (funcname=e.args[1], args=e.args[2:end])
    elseif e.head == :do
        # do-call: map(a) do ... end
        @assert length(e.args) == 2  # TODO: any issues with supporting more args?
        @assert e.args[1].head == :call
        @assert e.args[2].head == :(->)
        fname = e.args[1].args[1]
        args = [e.args[2:end]..., e.args[1].args[2:end]...]  # do-arg first, then all args from within the call
        (funcname=fname, args)
    else
        # anything else
        # e.g., a[b], macro call, what else?
        nothing
    end
end

add_prev_arg_if_needed(func_fullname, args, prev::Nothing) = args
function add_prev_arg_if_needed(func_fullname, args, prev)
    # check if there are any prev placeholders in args already
    need_to_append = !any(args) do arg
        occursin_expr(ee -> is_pipecall(ee) ? StopWalk(ee) : ee == PREV_PLACEHOLDER, arg)
    end
    if need_to_append
        name = string(unqualified_name(func_fullname))
        isletter(name[1]) || @warn "Pipeline step top-level function is an operator. An argument with the previous step results is still appended." func=name args
        [args; [prev]]
    else
        args
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

transform_args(func_fullname, args) = map(enumerate(args)) do (i, arg)
    transform_arg(arg, func_fullname, i)
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

# expected number of arguments in argix'th argument of func if this arg is a function itself
# this sets the minimum, additional underscores always get converted to more arguments
func_nargs(func, argix) = func_nargs(Val(unqualified_name(func)), argix)
func_nargs(func::Val, argix::Union{Int, Symbol, Nothing}) = func_nargs(func, Val(argix))
func_nargs(func::Val, argix::Val) = 0  # so that _ is replaced everywhere
func_nargs(func::Val{:mapmany}, argix::Val{2}) = 2
func_nargs(func::Val{:product}, argix::Val{1}) = 2
func_nargs(func::Union{Val{:innerjoin}, Val{:leftgroupjoin}}, argix::Val{3}) = 2
func_nargs(func::Union{Val{:innerjoin}, Val{:leftgroupjoin}}, argix::Val{4}) = 2

is_pipecall(e) = false
is_pipecall(e::Expr) = e.head == :macrocall && e.args[1] ∈ (Symbol("@pipe"), Symbol("@p"), Symbol("@pipefunc"), Symbol("@f"))

# if contains "_"-like placeholder: transform to function
# otherwise keep as-is
function func_or_body_to_func(e, nargs::Int)
    nargs = max(nargs, max_placeholder_n(e))

    args = [gensym("x_$i") for i in 1:nargs]    
    e_replaced = replace_arg_placeholders(e, args)
    if e_replaced != e
        if is_lambda_function(e_replaced)
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

is_lambda_function(e) = false
is_lambda_function(e::Expr) = e.head == :(->)
function max_placeholder_n(e)
    nargs = 0
    prewalk(e) do ee
        if is_pipecall(ee)
            nargs = max(nargs, max_placeholder_n_inner(ee))
            return StopWalk(ee)
        end
        if is_arg_placeholder(ee)
            nargs = max(nargs, arg_placeholder_n(ee))
        end
        return ee
    end
    return nargs
end
function max_placeholder_n_inner(e)
    nargs = 0
    seen_pipe = false
    prewalk(e) do ee
        if is_pipecall(ee)
            seen_pipe && return StopWalk(ee)
            seen_pipe = true
        end
        if is_outer_arg_placeholder(ee)
            nargs = max(nargs, outer_arg_placeholder_n(ee))
        end
        return ee
    end
    return nargs
end

" Replace function arg placeholders (like `_`) with corresponding symbols from `args`. Processes a single level of `@p` nesting. "
replace_arg_placeholders(expr, args::Vector{Symbol}) = prewalk(expr) do ee
    is_pipecall(ee) && return StopWalk(replace_arg_placeholders_within_inner_pipe(ee, args))
    is_arg_placeholder(ee) ? args[arg_placeholder_n(ee)] : ee
end
replace_arg_placeholders_within_inner_pipe(expr, args::Vector{Symbol}) = let
    seen_pipe = false
    prewalk(expr) do e
        if is_pipecall(e)
            seen_pipe && return StopWalk(e)
            seen_pipe = true
        end
        is_outer_arg_placeholder(e) ? args[outer_arg_placeholder_n(e)] : e
    end
end

" Replace symbols in `expr` according to `syms_replacemap`. "
replace_in_pipeexpr(expr, syms_replacemap::Dict) = prewalk(expr) do ee
    is_pipecall(ee) && return StopWalk(ee)
    haskey(syms_replacemap, ee) && return syms_replacemap[ee]
    return ee
end
