# Overview

Piping package for Julia.
`DataPipes` inteface is designed with common data processing functions (e.g., `map` and `filter`) in mind, but is not specifically tied to them and can be used for all kinds of pipelines. This package is extensively tested, and I almost always use it myself for data manipulation.

Even with multiple existing implementations of the general piping concept, I didn't find one that is convenient enough while still remaining general.
Unlike many ([1](https://github.com/jkrumbiegel/Chain.jl), [2](https://github.com/FNj/Hose.jl), [3](https://github.com/oxinabox/Pipe.jl); all?) other alternatives, `DataPipes`:
- Gets rid of basically all the boilerplate for functions that follow the common Julia argument order
- Can be plugged in as a step of a vanilla pipeline
- Can easily export the result of an intermediate step

If I missed another implementation that also ticks these points, please let me know.

`DataPipes` tries to minimally modify regular Julia syntax and aims to stay composable both with other instruments (vanilla pipelines, other packages) and with itself (nested pipes). See usage examples below.

# Usage

Simple example of processing tabular data:

```julia
@p begin
    tbl
	filter(!any(ismissing, _))
    filter(_.id > 6)
    groupview(_.group)
    map(sum(_.age))
end
```

This is adapted from the `Chain.jl` example, replacing all `DataFrames.jl`-specific operations with general functions applicable to a wide range of tables: eg, it works with `StructArrays`.

For comparison, the original `Chain.jl` example:

```julia
@chain df begin
  dropmissing
  filter(:id => >(6), _)
  groupby(:group)
  combine(:age => sum)
end
```

`DataPipes.jl` remains convenient for processing nested data as well. See [the Pluto notebook](https://aplavin.github.io/DataPipes.jl/examples/notebook.html) for a set of worked out data manipulation steps, and for more extensive documentation.
