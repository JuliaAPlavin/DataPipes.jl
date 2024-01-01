macro pipe(block) pipe_macro(block) end
macro pipe(exprs...) pipe_macro(exprs) end
macro pipeDEBUG(block) pipe_macro(block; debug=true) end
macro pipeDEBUG(exprs...) pipe_macro(exprs; debug=true) end
macro pipefunc(block) pipefunc_macro(block) end
macro pipefunc(exprs...) pipefunc_macro(exprs) end

function pipefunc_macro(block)
    arg = gensym("pipefuncarg")
    blocktype, steps = process_block(block, arg)
    @remove_linenums! :( $(arg) -> $(map(final_expr, steps)...) ) |> esc
end

function pipe_macro(block; debug=false)
    blocktype, steps = process_block(block, nothing)
    isempty(steps) && return nothing
    res_arg = filtermap(res_arg_if_propagated, steps) |> last
    all_exports = mapreduce(exports, vcat, steps)
    all_assigns = mapreduce(assigns, vcat, steps)
    if debug
        all_res_args = filtermap(res_arg_if_present, steps)
        exprs = map(steps) do s
            e = final_expr(s)
            res = res_arg_if_present(s)
            isnothing(res) ? e : @remove_linenums! :(
                $e;
                push!(_pipe, $res)
            )
        end
        @remove_linenums! quote
            global ($([all_assigns..., res_arg]...),)
            global _pipe = []
            let $(all_res_args...)
                $(exprs...)
                $(res_arg)
            end
        end |> esc
    elseif blocktype == :let
        @remove_linenums! quote
            ($([all_exports..., res_arg]...),) = let ($(all_assigns...))
                $(map(final_expr, steps)...)
                ($([all_exports..., res_arg]...),)
            end
            $(res_arg)
        end |> esc
    elseif blocktype == :begin
        @remove_linenums! quote
            $(map(final_expr, steps)...)
            $(res_arg)
        end |> esc
    else
        error("Unexpected block type: $blocktype")
    end
end

function process_block(block, initial_arg)
    blocktype, exprs = get_exprs(block)
    exprs = expand_docstrings(exprs)
    steps = []
    prev = initial_arg
    for e in exprs
        step = process_pipe_step(e, prev)
        res_arg = res_arg_if_propagated(step)
        prev = isnothing(res_arg) ? prev : res_arg
        push!(steps, step)
    end
    return blocktype, steps
end

struct BroadcastedExpr
    expr
end

get_exprs(block) = :let, [block]
get_exprs(block::Tuple) = :let, block
get_exprs(block::Expr) = if block.head == :block
    # block `begin ... end`
    exprs = block.args
    exprs_noln = filter(e -> !(e isa LineNumberNode), exprs)
    length(exprs_noln) == 1 && return get_exprs(only(exprs_noln))
    :begin, exprs
elseif block.head == :let
    # block `let ... end`
    @assert length(block.args) == 2
    @assert isempty(block.args[1].args)
    @assert block.args[2].head == :block
    :let, get_exprs(block.args[2])[2]
elseif block.head == :call && block.args[1] ∈ (Symbol("|>"), Symbol(".|>"))
    # piped functions like `a |> f1 |> f2`
    exprs = []
    while block isa Expr && block.head == :call && block.args[1] ∈ (Symbol("|>"), Symbol(".|>"))
        pushfirst!(exprs, block.args[1] == Symbol(".|>") ? BroadcastedExpr(block.args[3]) : block.args[3])
        block = block.args[2]
    end
    pushfirst!(exprs, block)
    :let, exprs
else
    # everything else
    :let, [block]
end

expand_docstrings(exprs) = mapreduce(vcat, exprs; init=[]) do e
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

function process_pipe_step(be::BroadcastedExpr, prev)
    prev_elt = gensym("prev_elt")
    next = gensym("res")
    e = be.expr
    e = prewalk(ee -> get(REPLACE_IN_PIPE, ee, ee), e)
    e = transform_pipe_step(e, prev_elt)
    e = replace_in_pipeexpr(e, Dict(PREV_PLACEHOLDER => prev_elt))
    e = :($(next) = ($prev_elt -> $(e)).($prev))
    return PipeStep(;
        expr_orig=be.expr,
        expr_transformed=e,
        res_arg=next,
        assigns=[],
        exports=[],
        is_aside=false, keep_asis=false, no_add_prev=false,
    )
end


# anything else, e.g. plain numbers or strings: keep as-is
transform_pipe_step(e, prev) = e
# symbol as the first pipeline step: keep as-is
transform_pipe_step(e::Symbol, prev::Nothing) = e
# symbol as latter pipeline steps: generally represents a function call
transform_pipe_step(e::Symbol, prev::Symbol) = e == PREV_PLACEHOLDER ? prev : :($(e)($(prev)))
function transform_pipe_step(e::Expr, prev::Union{Symbol, Nothing})
    if !isnothing(prev) && is_qualified_name(e)
        # qualified function name, as in Iterators.map
        return occursin_expr(==(PREV_PLACEHOLDER), e) ? e : :($(e)($(prev)))
    end

    fcall = dissect_function_call(e)
    isnothing(fcall) && return e  # pipe step not a function call: keep it as-is
    args = fcall.args
    args = map(args) do arg
        modify_argbody(func_or_body_to_func ∘ process_implicit_pipe, arg)
    end
    args = add_prev_arg_if_needed(fcall.funcname, args, prev)
    args = sort(args; by=a -> a isa Expr && a.head == :parameters, rev=true)
    :( $(fcall.funcname)($(args...)) )
end

process_implicit_pipe(arg) = 
    if is_implicitpipe(arg)
        @assert count_expr(==(IMPLICIT_PIPE_ARG), lambda_function_args(arg)) == 1
        block = lambda_function_body(arg)
        iarg = gensym("innerpipe_arg")
        blocktype, steps = process_block(block, iarg)
        new_args = replace_in_pipeexpr(lambda_function_args(arg), Dict(:__ => iarg))
        expr = @remove_linenums! :( ($(new_args...),) -> $(map(final_expr, steps)...) )
        if lambda_function_args(arg) == (IMPLICIT_PIPE_ARG,)
            # not sure what replacement to do when multiple args
            expr = replace_arg_placeholders_within_inner_pipe(expr, [iarg])
        end
        expr
    else
        arg
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
        occursin_expr(arg) do ee
            is_pipecall(ee) ? StopWalk(ee) :
            is_kwexpr(ee) ? ContinueWalk(ee.args[2]) :
            ee == PREV_PLACEHOLDER
        end
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


is_pipecall(e) = is_macropipe(e) || is_implicitpipe(e)

is_macropipe(e) = false
is_macropipe(e::Expr) = e.head == :macrocall && e.args[1] ∈ (S"@pipe", S"@p", S"@pipefunc", S"@f")

# implicit pipe: function argument that is a lambda function,
# with an argument or a part of an argument named IMPLICIT_PIPE_ARG
is_implicitpipe(e) = false
is_implicitpipe(e::Expr) = is_lambda_function(e) && occursin_expr(==(IMPLICIT_PIPE_ARG), lambda_function_args(e))


function func_or_body_to_func(e)
    if is_lambda_function(e) && !any(is_arg_placeholder, lambda_function_args(e))
        # already a function with explicitly specified arguments - no placeholders
        # don't replace anything within, even if there are underscores
        return e
    end

    nargs = max_placeholder_n(e)
    args = [gensym("x_$i") for i in 1:nargs]
    e_replaced = replace_arg_placeholders(e, args)
    if e_replaced != e
        if is_lambda_function(e_replaced)
            # already a function definition
            e_replaced
        else
            # just function body, need to turn into definition
            @remove_linenums! :(($(args...),) -> $e_replaced)
        end
    else
        e
    end
end

function max_placeholder_n(e)
    nargs = 0
    prewalk(e) do ee
        is_kwexpr(ee) && return ContinueWalk(ee.args[2])
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
        is_kwexpr(ee) && return ContinueWalk(ee.args[2])
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
    is_kwexpr(ee) && return reassemble_kwexpr(ee, StopWalk(ee.args[1]), replace_arg_placeholders(ee.args[2], args))
    ignore_underscore_within(ee) && return StopWalk(ee)
    is_pipecall(ee) && return StopWalk(replace_arg_placeholders_within_inner_pipe(ee, args))
    is_arg_placeholder(ee) ? args[arg_placeholder_n(ee)] : ee
end
replace_arg_placeholders_within_inner_pipe(expr, args::Vector{Symbol}) = let
    seen_pipe = false
    prewalk(expr) do ee
        is_kwexpr(ee) && return reassemble_kwexpr(ee, StopWalk(ee.args[1]), ee.args[2])
        if is_pipecall(ee)
            seen_pipe && return StopWalk(ee)
            seen_pipe = true
        end
        is_outer_arg_placeholder(ee) ? args[outer_arg_placeholder_n(ee)] : ee
    end
end

" Replace symbols in `expr` according to `syms_replacemap`. "
replace_in_pipeexpr(expr, syms_replacemap::Dict) = prewalk(expr) do ee
    is_kwexpr(ee) && return reassemble_kwexpr(ee, StopWalk(ee.args[1]), replace_in_pipeexpr(ee.args[2], syms_replacemap))
    is_pipecall(ee) && return StopWalk(ee)
    haskey(syms_replacemap, ee) && return syms_replacemap[ee]
    return ee
end
