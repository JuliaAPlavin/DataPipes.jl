module DataPipes

export @pipe, @asis, mapmany, mutate

include("utils.jl")
include("pipe.jl")
include("data_functions.jl")

end
