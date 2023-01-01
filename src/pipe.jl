macro pipe(block) pipe_macro(block) end
macro pipe(exprs...) pipe_macro(exprs) end
macro pipeDEBUG(block) pipe_macro(block; debug=true) end
macro pipeDEBUG(exprs...) pipe_macro(exprs; debug=true) end
macro pipefunc(block) pipefunc_macro(block) end
macro pipefunc(exprs...) pipefunc_macro(exprs) end

function pipefunc_macro(block)
    arg = gensym("pipefuncarg")
    steps = process_block(block, arg)
    :( $(arg) -> $(map(final_expr, steps)...) ) |> esc
end

function pipe_macro(block; debug=false)
    steps = process_block(block, nothing)
    res_arg = filtermap(res_arg_if_propagated, steps) |> last
    all_exports = mapmany(exports, steps)
    all_assigns = mapmany(assigns, steps)
    if debug
        all_res_args = filtermap(res_arg_if_present, steps)
        exprs = map(steps) do s
            e = final_expr(s)
            res = res_arg_if_present(s)
            isnothing(res) ? e : :(
                $e;
                push!(_pipe, $res)
            )
        end
        quote
            global ($([all_assigns..., res_arg]...),)
            global _pipe = []
            let $(all_res_args...)
                $(exprs...)
                $(res_arg)
            end
        end |> esc
    else
        quote
            ($([all_exports..., res_arg]...),) = let ($(all_assigns...))
                $(map(final_expr, steps)...)
                ($([all_exports..., res_arg]...),)
            end
            $(res_arg)
        end |> esc
    end
end

function process_block(block, initial_arg)
    exprs = get_exprs(block) |> expand_docstrings
    steps = []
    prev = initial_arg
    for e in exprs
        step = process_pipe_step(e, prev)
        res_arg = res_arg_if_propagated(step)
        prev = isnothing(res_arg) ? prev : res_arg
        push!(steps, step)
    end
    return steps
end

get_exprs(block) = [block]
get_exprs(block::Tuple) = block
get_exprs(block::Expr) = if block.head == :block
    # block like `begin ... end`
    exprs = block.args
    exprs_noln = filter(e -> !(e isa LineNumberNode), exprs)
    if length(exprs_noln) == 1
        get_exprs(only(exprs_noln))
    else
        exprs
    end
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

expand_docstrings(exprs) = mapreduce(vcat, exprs) do e
    if e isa Expr && e.head == :macrocall && e.args[1] == GlobalRef(Core, S"@doc")
        @assert e.args[2] isa LineNumberNode
        @assert e.args[3] isa String
        e.args[3:4]
    else
        [e]
    end
end

Base.@kwdef struct PipeStep
    expr_orig
    expr_transformed
    res_arg::Symbol
    assigns::Vector{Symbol}
    exports::Vector{Symbol}
    # flags:
    is_aside::Bool
    keep_asis::Bool
    no_add_prev::Bool
end

final_expr(p::PipeStep) = p.expr_transformed
exports(p::PipeStep) = p.exports
assigns(p::PipeStep) = p.assigns
res_arg_if_present(p::PipeStep) = p.res_arg
res_arg_if_propagated(p::PipeStep) = p.is_aside ? nothing : p.res_arg

final_expr(e::LineNumberNode) = e
exports(e::LineNumberNode) = []
assigns(e::LineNumberNode) = []
res_arg_if_present(e::LineNumberNode) = nothing
res_arg_if_propagated(e::LineNumberNode) = nothing

process_pipe_step(e::LineNumberNode, prev) = e
function process_pipe_step(e, prev)
    e_orig = e
    e, exports = process_exports(e)
    e, is_aside = search_macro_flag(e, S"@aside")
    assign_lhs, e, assigns = split_assignment(e)
    next = gensym("res")
    e, keep_asis = search_macro_flag(e, S"@asis")
    e, no_add_prev = search_macro_flag(e, S"@_")
    if !keep_asis
        e = prewalk(ee -> get(REPLACE_IN_PIPE, ee, ee), e)
        e = transform_pipe_step(e, no_add_prev ? nothing : prev)
        e = replace_in_pipeexpr(e, Dict(PREV_PLACEHOLDER => prev))
    end
    e = if isnothing(assign_lhs)
        :($(next) = $(e))
    else
        :($(next) = $(assign_lhs) = $(e))
    end
    return PipeStep(;
        expr_orig=e_orig,
        expr_transformed=e,
        res_arg=next,
        assigns,
        exports,
        is_aside, keep_asis, no_add_prev,
    )
end

# symbol as the first pipeline step: keep as-is
transform_pipe_step(e::Symbol, prev::Nothing) = e
# symbol as latter pipeline steps: generally represents a function call
transform_pipe_step(e::Symbol, prev::Symbol) = e == PREV_PLACEHOLDER ? prev : :($(e)($(prev)))
function transform_pipe_step(e, prev::Union{Symbol, Nothing})
    fcall = dissect_function_call(e)
    if !isnothing(fcall)
        args = fcall.args
        args = map(args) do arg
            if is_lambda_function(arg) && occursin_expr(==(IMPLICIT_PIPE_ARG), lambda_function_args(arg))
                # pipe step function argument is a lambda function, with an argument or a part of an argument named IMPLICIT_PIPE_ARG
                @assert count_expr(==(IMPLICIT_PIPE_ARG), lambda_function_args(arg)) == 1
                block = lambda_function_body(arg)
                iarg = gensym("innerpipe_arg")
                steps = process_block(block, iarg)
                new_args = replace_in_pipeexpr(lambda_function_args(arg), Dict(:__ => iarg))
                expr = :( ($(new_args...),) -> $(map(final_expr, steps)...) )
                if lambda_function_args(arg) == (IMPLICIT_PIPE_ARG,)
                    # not sure what replacement to do when multiple args
                    expr = replace_arg_placeholders_within_inner_pipe(expr, [iarg])
                end
                expr
            else
                arg
            end
        end
        args = transform_args(fcall.funcname, args)
        args = add_prev_arg_if_needed(fcall.funcname, args, prev)
        args = sort(args; by=a -> a isa Expr && a.head == :parameters, rev=true)
        :( $(fcall.funcname)($(args...)) )
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
        e.args[1].head == :macrocall && return nothing  # don't process _ in macro arguments; __ is substituted elsewhere
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
    need_to_append = !any([func_fullname; args]) do arg
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
    proc_f(e::Expr) = if e.head == :macrocall && e.args[1] == S"@export"
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
is_pipecall(e::Expr) = let
    is_macro = e.head == :macrocall && e.args[1] ∈ (S"@pipe", S"@p", S"@pipefunc", S"@f")
    is_implicitpipe = is_lambda_function(e) && lambda_function_args(e) == (IMPLICIT_PIPE_ARG,)
    return is_macro || is_implicitpipe
end

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
lambda_function_args(e::Expr) = if e.args[1] isa Symbol
    (e.args[1],)
else
    @assert e.args[1].head == :tuple
    Tuple(e.args[1].args)
end
lambda_function_body(e::Expr) = e.args[2]

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
    ignore_underscore_within(ee) && return StopWalk(ee)
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
