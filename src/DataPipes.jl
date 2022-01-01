module DataPipes

export @pipe, @pipefunc, @p, @pf, @f, mapmany, mutate, mutate_flat, mutate_seq, mutate_rec, filtermap

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

const var"@p" = var"@pipe"
const var"@pf" = var"@pipefunc"
const var"@f" = var"@pipefunc"


# define placeholder characters:

## result of the previous pipeline step
const PREV_PLACEHOLDER = :__

## the only lambda argument name so that it's treated as implicit inner pipe
const IMPLICIT_PIPE_ARG = PREV_PLACEHOLDER

## function arguments
is_arg_placeholder(x) = !isnothing(arg_placeholder_n(x))
arg_placeholder_n(x) = nothing
arg_placeholder_n(x::Symbol) = let
    x == :_ && return 1
    m = match(r"^_(\d)$", string(x))
    !isnothing(m) && return parse(Int, m[1])
    return nothing
end

## function arguments from the outer pipe - a single level is supported
is_outer_arg_placeholder(x) = !isnothing(outer_arg_placeholder_n(x))
outer_arg_placeholder_n(x) = nothing
outer_arg_placeholder_n(x::Symbol) = let
    m = match(r"^(.+)ꜛ$", string(x))
    !isnothing(m) && return arg_placeholder_n(Symbol(m[1]))
    return nothing
end

module NoAbbr
import ..@pipe, ..@pipefunc
export @pipe, @pipefunc
end

end
