module DataPipes

export @pipe, @pipefunc, @p, @pf, @f, @asis, mapmany, mutate, mutate_

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

const var"@p" = var"@pipe"
const var"@pf" = var"@pipefunc"
const var"@f" = var"@pipefunc"

module NoAbbr
import ..@pipe, ..@pipefunc, ..@asis, ..mapmany, ..mutate, ..mutate_
export @pipe, @pipefunc, @asis, mapmany, mutate, mutate_
end

end
