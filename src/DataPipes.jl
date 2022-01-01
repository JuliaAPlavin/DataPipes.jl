module DataPipes

export @pipe, @pipefunc, @asis, mapmany, mutate, mutate_

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

end
