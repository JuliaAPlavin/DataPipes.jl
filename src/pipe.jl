macro asis(expr)
    if occursin_expr(ee -> is_pipecall(ee) ? StopWalk(ee) : ee == :↑, expr)
        data = gensym("data")
        body = prewalk(expr) do ee
            is_pipecall(ee) && return StopWalk(ee)
            ee == :↑ && return data
            return ee
        end
        :($(esc(data)) -> $(esc(body)))
    else
        expr
    end
end


macro pipe(block)
    pipe_macro(block)
end

macro pipe(exprs...)
    pipe_macro(exprs)
end

macro pipefunc(block)
    pipefunc_macro(block)
end

macro pipefunc(exprs...)
    pipefunc_macro(exprs)
end

function pipe_macro(block)
    exprs = get_exprs(block)
    exprs_processed = filter(!isnothing, map(pipe_process_expr, exprs))
    quote
        exprs = ($(exprs_processed...),)
        foldl(|>, exprs)
    end
end

function pipefunc_macro(block)
    exprs = get_exprs(block)
    exprs_processed = filter(!isnothing, map(pipe_process_expr, exprs))
    quote
        exprs = ($(exprs_processed...),)
        data -> foldl(|>, exprs, init=data)
    end
end

get_exprs(block::Symbol) = [block]
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
    throw("Unknown block head: $(block.head)")
end

is_func_expr(e) = false
is_func_expr(e::Expr) = e.head == :(->)

pipe_process_expr(e::LineNumberNode) = nothing
pipe_process_expr(e::Symbol) = esc(e)
function pipe_process_expr(e::Expr)
    if e.head == :call
        fname = func_name(e.args[1])
        data = gensym("data")
        :($(esc(data)) -> $(pipe_process_exprfunc(Val(fname), e.args[2:end], data) |> esc))
    elseif e.head == :do
        @assert length(e.args) == 2
        @assert e.args[1].head == :call
        fname = e.args[1].args[1]
        @assert e.args[2].head == :(->)
        body = e.args[2]
        data = gensym("data")
        :($(esc(data)) -> $(pipe_process_exprfunc(Val(fname), [body], data) |> esc))
    else
        esc(e)
    end
end

func_name(e::Symbol) = e
func_name(e::Expr) = let
    @assert e.head == :.
    @assert length(e.args) == 2
    return e.args[2].value
end

function pipe_process_exprfunc(func, args, data)
    args_processed = map(enumerate(args)) do (i, arg)
        if arg isa Expr && arg.head == :kw
            @assert length(arg.args) == 2
            key = arg.args[1]
            value = arg.args[2]
            nargs = func_nargs(func, key)
            Expr(:kw, key, func_or_body_to_func(value, nargs, data))
        else
            nargs = func_nargs(func, Val(i))
            func_or_body_to_func(arg, nargs, data)
        end
    end
    if need_append_data_arg(args)
        :( $(val(func))($(args_processed...), $data) )
    else
        :( $(val(func))($(args_processed...)) )
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
is_pipecall(e::Expr) = e.head == :macrocall && e.args[1] == Symbol("@pipe")

function func_or_body_to_func(e, nargs::Int, data::Symbol)
    args = [gensym("x_$i") for i in 1:nargs]
    syms_replacemap = Dict(Symbol("_"^i) => args[i] for i in 1:nargs)
    prewalk(e) do ee
        is_pipecall(ee) && return StopWalk(ee)
        if ee isa Symbol && all(c == '_' for c in string(ee)) && !haskey(syms_replacemap, ee)
            throw("Unknown all-underscore variable `$(ee)` in pipe. Too many underscores?")
        end
    end
    e = replace_in_pipeexpr(e, Dict(:↑ => data))
    if occursin_expr(ee -> is_pipecall(ee) ? StopWalk(ee) : haskey(syms_replacemap, ee), e)
        body = replace_in_pipeexpr(e, syms_replacemap)
        if body isa Expr && body.head == :(->)
            # already a function definition
            body
        else
            # just function body, need to turn into definition
            :(($(args...),) -> $body)
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
