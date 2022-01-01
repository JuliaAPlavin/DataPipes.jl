module DataPipes

export @pipe, @pipefunc, @asis, mapmany, mutate, mutate_

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

module Abbr
import ..@pipe, ..@pipefunc
const var"@p" = var"@pipe"
const var"@pf" = var"@pipefunc"
export @p, @pf
end

end
