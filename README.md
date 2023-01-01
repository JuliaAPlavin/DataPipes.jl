# DataPipes.jl

Function piping with the focus on making general data processing boilerplate-free.

[![CI](https://github.com/aplavin/DataPipes.jl/actions/workflows/main.yml/badge.svg)](https://github.com/aplavin/DataPipes.jl/actions/workflows/main.yml) `DataPipes.jl` is extensively tested with full coverage and more test lines than the actual code.

_Questions other than direct bug reports are best asked in the [discouse thread](https://discourse.julialang.org/t/ann-datapipes-jl/60734)._


There are multiple implementation of the piping concept in Julia: [1](https://github.com/c42f/Underscores.jl), [2](https://github.com/jkrumbiegel/Chain.jl), [3](https://github.com/FNj/Hose.jl), [4](https://github.com/oxinabox/Pipe.jl), maybe even more. `DataPipes` design is focused on usual data processing and analysis tasks. What makes `DataPipes` distinct from other packages is that it ticks all these points:

- [x] Gets rid of basically all boilerplate for common data processing functions:
```julia
@p tbl |> filter(_.a > 5) |> map(_.b + _.c)
```
- [x] Can be inserted in as a step of a vanilla Julia pipeline without modifying the latter:
```julia
tbl |> sum  # before
tbl |> @f(map(_ ^ 2) |> filter(_ > 5)) |> sum  # after
```
- [x] Can define a function transforming the data instead of immediately applying it
```julia
func = @f map(_ ^ 2) |> filter(_ > 5) |> sum  # define func
func(tbl)  # apply it
```
- [x] Supports easily exporting the result of an intermediate pipeline step
```julia
@p let
    tbl
    @export tbl_filt = filter(_.a > 5)  # export a single intermediate result
    map(_.b + _.c)
end

@p begin  # use begin instead of let to make all intermediate results available afterwards
    tbl
    tbl_filt = filter(_.a > 5)
    map(_.b + _.c)
end

# tbl_filt is available here
```
- [x] Provides no-boilerplate nesting
```julia
@p let
	"a=1 b=2 c=3"
	split
	map() do __  # `__` turns the inner function into a pipeline
		split(__, '=')
		Symbol(__[1]) => parse(Int, __[2])
	end
	NamedTuple
end  # == (a = 1, b = 2, c = 3)
```


As demonstrated, `DataPipes` tries to minimally modify regular Julia syntax and stays fully composable both with other instruments _(vanilla pipelines)_ and with itself _(nested pipes)_.

These traits make `DataPipes` convenient for both working with flat tabular data, and for processing nested structures. An example of the former:
```julia
@p begin
    tbl
    filter(!any(ismissing, _))
    filter(_.id > 6)
    groupview(_.group)
    map(sum(_.age))
end
```
_(adapted from the Chain.jl README; all DataFrames-specific operations replaced with general functions)_


See [the Pluto notebook](https://aplavin.github.io/DataPipes.jl/examples/notebook.html) for more examples and more extensive `DataPipes` syntax description.
