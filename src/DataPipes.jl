module DataPipes

export @pipe, @pipeDEBUG, @pipefunc, @p, @pDEBUG, @pf, @f

include("utils.jl")
include("pipe.jl")

const var"@p" = var"@pipe"
const var"@pDEBUG" = var"@pipeDEBUG"
const var"@pf" = var"@pipefunc"
const var"@f" = var"@pipefunc"


" Result of the previous pipeline step "
const PREV_PLACEHOLDER = :__
const PREV_PLACEHOLDER_OUTER = :__ꜛ

" Name of the lambda argument treated as an implicit inner pipe "
const IMPLICIT_PIPE_ARG = PREV_PLACEHOLDER

" Replacements to perform within pipes, before other transformations. "
const REPLACE_IN_PIPE = Dict(S"@o" => S"@optic")

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

## expressions where DataPipes won't replace `_` placeholders with lambda argument
ignore_underscore_within(e) = false
ignore_underscore_within(e::Expr) = e.head == :macrocall && e.args[1] ∈ (S"@optic",)

module NoAbbr
import ..@pipe, ..@pipefunc
export @pipe, @pipefunc
end

end
