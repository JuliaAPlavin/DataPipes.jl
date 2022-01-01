# Overview

Yet another piping package for Julia. Even with multiple existing implementations of this general concept, I didn't find one that is convenient enough [for my usecases] while still remaining general. Additionally, I became curious in how metaprogramming works, so developing `DataPipes` helped me understand a lot of that.

`DataPipes` inteface is designed with common data processing functions (e.g., `map` and `filter`) in mind, but is not specifically tied to them and can be used for all kinds of pipelines. This package is extensively tested, and I almost always use it myself for data manipulation.

Unlike many ([1](https://github.com/jkrumbiegel/Chain.jl), [2](https://github.com/FNj/Hose.jl), [3](https://github.com/oxinabox/Pipe.jl); all?) other alternatives, `DataPipes`:
- Gets rid of basically all the boilerplate for functions that follow the common argument order
- Can be plugged in as a step of a vanilla pipeline
- Can define a function instead of immediately applying it
- Can easily export the result of an intermediate step

If I missed another implementation that also ticks these points, please let me know.

`DataPipes` tries to minimally modify regular Julia syntax and aims to stay composable both with other instruments (e.g. vanilla pipelines) and with itself (nested pipes). See usage examples below.

# Examples

## Basic

`DataPipes` exports both full and abbreviated forms of its macros: `@pipe === @p`, `@pipefunc === @f`. Full forms alone can be loaded with `using DataPipes.NoAbbr` instead of `using DataPipes`.
```julia
julia> using DataPipes
```

Short and simple pipelines can be written with the familiar Julia pipe syntax:
```julia
julia> @p 1:4 |> map(_^2) |> filter(exp(_) > 5)
3-element Vector{Int64}:
  4
  9
 16
```

More complex sequences are better split into multiple lines:
```julia
julia> @p begin
           [1, 2, 3, 4]
           map((a=_, b=_^2, c=1:_))
           filter(length(_.c) >= 2)
           map((; _.a, s=sum(_.c)))
       end
3-element Vector{NamedTuple{(:a, :s), Tuple{Int64, Int64}}}:
 (a = 2, s = 3)
 (a = 3, s = 6)
 (a = 4, s = 10)
```
However, these two forms are completely equivalent, pipeline steps undergo the same transformations either way.

Lambdas in keyword arguments work just fine:
```julia
julia> @p sort(1:5, by=_ % 2)
5-element Vector{Int64}:
 2
 4
 1
 3
 5
```

Multivariate lambdas are fully supported: `__` (double underscore) is the placeholder for the second argument, `___` for the third, etc:
```julia
julia> @p map(_ + __, 1:3, 10:12)
3-element Vector{Int64}:
 11
 13
 15

julia> @p map(_ + ___, 1:3, 100:102, 10:12)
3-element Vector{Int64}:
 11
 13
 15
```

`DataPipes` also fits within vanilla Julia pipelines:
```julia
julia> [1, 2, 3, 4] |> @f(map(_^2)) |> sum
30
```
and can be used to create standalone functions:
```julia
julia> func = @f map(_^2) |> filter(exp(_) > 5);

julia> func([1, 2, 3, 4])
3-element Vector{Int64}:
  4
  9
 16
```

## Interoperability

The `DataPipes` package can be used not only with base Julia functions, but with 3rd-party packages as well. Any function that follows the common argument order remains as convenient to use as base functions.

Several examples using `SplitApplyCombine.jl`:
```julia
julia> using SplitApplyCombine

julia> data = [
           (name="A B", values=[1, 2, 3, 4]),
           (name="C", values=[5, 6]),
       ];
```

Group and aggregate:
```julia
julia> @p begin
           data
           mapmany(_.values, __)
           group(_ % 2)
           map(sum)
       end
2-element Dictionaries.Dictionary{Int64, Int64}
 1 │ 9
 0 │ 12
```

Join, also illustrating two-argument lambdas:
```julia
julia> @p innerjoin(length(_.name), length(_), (a=_.name, b=__), data, ["", "A", "DEF", "B"])
3-element Vector{NamedTuple{(:a, :b), Tuple{String, String}}}:
 (a = "C", b = "A")
 (a = "A B", b = "DEF")
 (a = "C", b = "B")
```


## Advanced

`DataPipes` supports referring to earlier results in the pipeline. The result of the previous step is always available as `↑` (type with `\uparrow`). Intemediate results can also be named for easier reuse:
```julia
julia> @p begin
           orig = [1, 2, 3, 4]
           map(_^2)
           filter(_ >= 4)
           sum(↑) / sum(orig)
       end
2.9
```

Effects of such assignments are not visible outside:
```julia
julia> orig
ERROR: UndefVarError: orig not defined
```

It is possible to explicitly export (propagate) assigned values from the pipeline as well:
```julia
julia> @p begin
           orig = [1, 2, 3, 4]
           map(_^2)
           @export filt = filter(_ >= 4)
           sum(↑) / sum(orig)
       end
2.9

julia> filt
3-element Vector{Int64}:
  4
  9
 16
```

More complex inner functions can be written with `do`-notation. The argument can stay anonymous (`_`) or be named, but its name should be explicitly written either way to prevent confusion:
```julia
julia> @p begin
           [1, 2, 3, 4]
           map() do _
               _^2
           end
           map() do x
               x + 1
           end
           sum
       end
34
```

Pipes can be nested within one another. In this case, to refer to `_` of the outer pipe from within the inner one, use `_1`:
```julia
julia> @p begin
           data
           map(@p(_1.name |> collect |> map(string(_)^2) |> join(↑, "")))
       end
2-element Vector{String}:
 "AA  BB"
 "CC"

julia> @p begin
           data
           map((;
            _.name,
            values=@p(_1.values |>
                      map(_^2) |>
                      map((n=_1.name, v=_)))
           ))
       end
2-element Vector{NamedTuple{(:name, :values), Tuple{String, Vector{NamedTuple{(:n, :v), Tuple{String, Int64}}}}}}:
 (name = "A B", values = [(n = "A B", v = 1), (n = "A B", v = 4), (n = "A B", v = 9), (n = "A B", v = 16)])
 (name = "C", values = [(n = "C", v = 25), (n = "C", v = 36)])
```

Finally, it is possible to add a pipeline step that is kept as-is and not transformed by `DataPipes`. This is not supposed to be generally useful, but sometimes such an escape hatch makes sense. If that's the case, just wrap a step with `@asis`: the only replacement performed in this case is substituting the previous result for `↑`.
```julia
julia> @p [1, 2, 3, 4] |> @asis(map(x -> x^2, ↑)) |> filter(exp(_) > 5)
3-element Vector{Int64}:
  4
  9
 16
```
