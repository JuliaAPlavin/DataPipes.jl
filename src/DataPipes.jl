@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    replace(read(path, String), "```julia" => "```jldoctest mylabel")
end module DataPipes

export @pipe, @pipefunc, @p, @pf, @f, @asis, mapmany, mutate, mutate_flat, mutate_seq, mutate_rec

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

const var"@p" = var"@pipe"
const var"@pf" = var"@pipefunc"
const var"@f" = var"@pipefunc"

module NoAbbr
import ..@pipe, ..@pipefunc, ..@asis
export @pipe, @pipefunc, @asis
end

end
