module DataPipes

export @pipe, @asis, mapmany, mutate, mutate_

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

end
