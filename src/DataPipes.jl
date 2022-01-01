@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    replace(read(path, String), "```julia" => "```jldoctest mylabel")
end module DataPipes

export @pipe, @pipefunc, @p, @pf, @f, mapmany, mutate, mutate_flat, mutate_seq, mutate_rec, filtermap

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

const var"@p" = var"@pipe"
const var"@pf" = var"@pipefunc"
const var"@f" = var"@pipefunc"


# define placeholder characters:

## result of the previous pipeline step
const PREV_PLACEHOLDER = :↑

## function arguments
is_arg_placeholder(x) = !isnothing(arg_placeholder_n(x))
arg_placeholder_n(x) = nothing
arg_placeholder_n(x::Symbol) = all(==('_'), string(x)) ? length(string(x)) : nothing

## function arguments from the outer pipe - a single level is supported
is_outer_arg_placeholder(x) = !isnothing(outer_arg_placeholder_n(x))
outer_arg_placeholder_n(x) = nothing
outer_arg_placeholder_n(x::Symbol) = let
    m = match(r"^(.+)1$", string(x))
    isnothing(m) && return nothing
    arg_placeholder_n(Symbol(m[1]))
end

module NoAbbr
import ..@pipe, ..@pipefunc
export @pipe, @pipefunc
end

end
