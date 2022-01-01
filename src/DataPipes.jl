module DataPipes

export @pipe, @pipefunc, @asis, mapmany, mutate, mutate_

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

module Abbr
import ..@pipe
const var"@p" = var"@pipe"
export @p
end

end
