### A Pluto.jl notebook ###
# v0.19.11

using Markdown
using InteractiveUtils

# ╔═╡ 586750fc-5b72-11ec-3858-6dfbd4edb6d9
using DataPipes

# ╔═╡ bb7c0cbf-2012-4f78-bf6c-ff918d729b75
using SplitApplyCombine

# ╔═╡ c5015ff8-cb95-4776-bcfd-a0203d2089cf
using Statistics

# ╔═╡ 2c793094-964f-4f50-8c12-6c5cd30b7228
using PlutoUI

# ╔═╡ c310bae2-624c-48f9-af30-5a6367ed61c9
md"""
# `DataPipes.jl` highlights
"""

# ╔═╡ d7f69973-d32f-410d-827c-2c279d8f3f74
md"""
!!! info "DataPipes.jl"
	Function piping with the focus on making general data processing boilerplate-free.
"""

# ╔═╡ 204b665f-c217-49ac-8d39-0f539bb880af
md"""
\
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
"""

# ╔═╡ f2db737b-da1e-4f89-a848-11a7a5362a21
md"""
# Usage overview
"""

# ╔═╡ 6ca26c7b-4adb-4787-bb9e-a9ff22d31bd2
md"""
Generate a random dataset to start with. It contains several people with their names and ages, and multiple weight + mood measurements for each:
"""

# ╔═╡ d5b99750-9b2a-427c-9615-3d41f13b41a2
data = map(1:15) do i
	(
		name=rand('A':'C') * String(rand('a':'z', 10)),
		age=rand(10:100),
		measurements=[
			(weight=rand(10:150), mood=rand(1:5))
			for j in 1:rand(1:20)
		],
	)
end

# ╔═╡ 2eb9cbc9-3344-48f2-805a-b76a167604a1
md"""
Simple data manipulation using Julia Base functions become cleaner with `DataPipes.jl`:
"""

# ╔═╡ 30713956-bcc3-4340-871a-04a990a13d57
@p let
	data
	filter(_.age > 30)
	map((;
		_.name,
		is_old=_.age > 70,
		have_many=length(_.measurements) > 10
	))
end

# ╔═╡ c60870e4-e44c-4608-8f0e-09958b947c07
md"""
More complex manipulations can be split into functions and called from the pipeline:
"""

# ╔═╡ 6dd43f36-8362-4cb2-83f9-e6ee9570a103
function process_measurements(ms)
	# some complex processing...
	@p ms |> filter(_.mood > 0) |> mean(_.weight / _.mood)
end

# ╔═╡ d0c1feb0-e947-4067-add3-06f4bb32d5df
md"""
This function works on plain Julia data structures and can be applied to a single array:
"""

# ╔═╡ 321603ae-5dbb-4937-8483-17f1ea7e492e
process_measurements(data[1].measurements)

# ╔═╡ ed5afdd6-db6b-4e03-9ff6-738fd64186ab
# process all objects:
@p let
	data
	map((;
		_.name,
		result=process_measurements(_.measurements),
	))
end

# ╔═╡ bed56650-1255-46c8-b797-453b3070faa3
md"""
Of course, this works with other packages as well. A notable example is `SplitApplyCombine.jl` that contains essential data processing functions like `group`:
"""

# ╔═╡ c98807a7-fdef-4f77-bc42-7fe6281a2ab1
d = @p let
	data
	group((is_old=_.age > 30,))
	map(length)
end

# ╔═╡ c2b7d864-f8b4-42c3-adaa-a4e900d5c387
d[(is_old=true,)]

# ╔═╡ 3a3425c4-17ba-41f2-86ec-fab349820591


# ╔═╡ 5f5a9d3b-5ced-4619-bfde-551cbbb041c8
md"""
`DataPipes.jl` pipes can be cleanly nested, both explicitly:
"""

# ╔═╡ 1920226f-85cf-4e8f-b72c-8a36b50e624f
@p let
	data
	map() do r
		(; r.name, cnts = @p r.measurements |> groupcount(_.mood))
	end
end

# ╔═╡ 6016fdbb-1622-4826-9a00-adb6cdc42274
md"""
... and implicitly:
"""

# ╔═╡ 0553e1a5-369f-4cee-b8b9-048ffc950f75
@p let
	data
	map() do __
		@aside name = __.name
		__.measurements
		groupcount(_.mood)
		(; name, cnts=__)
	end
end

# ╔═╡ 5e8cbdd9-31d7-410a-8bb5-e6177db7eba7
md"""
The latter format is convenient for longer pipelines in the inner function.
"""

# ╔═╡ 17cc402f-8b25-4f23-ac08-d6e8290ec0f7
md"""
# Syntax
"""

# ╔═╡ 8ffd15fe-9576-4e51-b44e-6fb6b8e96103
md"""
## Essentials
"""

# ╔═╡ c9f60e22-a44d-4d40-ae7f-1a7354ec9842
md"""
The **main interface of `DataPipes` is the `@p` macro**. It signifies the pipeline context where all transformations happen.
"""

# ╔═╡ fe93fe81-05c8-4715-8ee8-6c61651b0f70
md"""
Short pipelines can be written in a single line:
"""

# ╔═╡ 959705f3-36ad-4a0e-8e59-8b62ab2c21b3
@p data |> filter(_.age > 40) |> map(_.name)

# ╔═╡ c073fa33-7911-464e-98fc-9c76d603b2fb
md"""
The block form is completely equivalent and tends to be more convenient for longer sequences:
"""

# ╔═╡ fe60a93a-2e86-43e5-ad35-b854fc522db6
@p let
	data
	filter(_.age > 40)
	map(_.name)
end

# ╔═╡ 39f6423b-2846-4a85-9047-d937c11b46ec
md"""
**`DataPipes` inserts the result of the previous pipeline step as the last function argument** by default. This is convenient for common data manipulation functions following Julia conventions as demonstrated above.

It remains easy to put the previous result anywhere in the expression manually using **`__` (double underscore)**:
"""

# ╔═╡ 91dbd9a0-7bbe-44d2-8e46-bf9f38a83b85
@p let
	"Hello World !"
	split(__, ' ')
	join(__, "! ")
end

# ╔═╡ 6aee48a0-344d-4777-bec2-6cd077f29a69
md"""
Another code modification done by `DataPipes` is **replacing `_` placeholders with anonymous function ("lambdas") arguments**. That is, `p map(_.a + 1)` is equivalent to `map(x -> x.a + 1)`.

Multivariate lambdas are supported through `_1`, `_2`, `_3`, ... syntax:
"""

# ╔═╡ 0a2921d0-f7eb-4eeb-a58b-6a658668aee3
@p map(_ + _2, 1:3, 10:12)

# ╔═╡ 18a06b16-632d-4b42-8ca8-db72993d7eca
@p map(_1 + _2, 1:3, 10:12)

# ╔═╡ bf441014-7f2f-4811-9641-5b83fd501ffc
md"""
Anonymous functions are transformed when they are keyword arguments as well:
"""

# ╔═╡ fdde50d3-0527-4914-affd-2a2d2071a922
@p data |> sort(by=_.age) |> map(_.age)

# ╔═╡ af92d4a9-a683-4ce7-b714-0aa63646b235
md"""
For more complex functions, the Julia **`do`-notation** is convenient and fully supported in `DataPipes`. The argument can stay anonymous (`_`) or be named, but its name should be explicitly written either way to prevent confusion:
"""

# ╔═╡ 0390197f-8444-497c-ab54-5d2740594d04
@p let
	data
	map() do _
		# many lines of code...
		_.name
	end
	map() do x
		# many lines of code...
		x[1:2]
	end
end

# ╔═╡ 44ab9fc7-0d22-444e-b92b-9c95341a71f0
md"""
## Intermediate
"""

# ╔═╡ af10d9dc-6005-4c99-909f-e68cbd1292eb
md"""
- Lambda functions consisting only of inner pipes is a common nesting pattern, especially with the `map` function. It has a more succint implicit syntax in `DataPipes`: the **lambda function body is treated as an inner pipe when one of its arguments is `__`** (double underscore).

The intuition is that `__` refers to the previous pipeline step everywhere in `DataPipes`, so assigning to `__` we effectively start a new pipe.\
Here is a simple string-to-namedtuple parsing example using this feature:
"""

# ╔═╡ 543fd79d-596f-4147-924d-99601431f2b7
@p let
	"a=1 b=2 c=3"
	split
	map() do __
		split(__, '=')
		Symbol(__[1]) => parse(Int, __[2])
	end
	NamedTuple
end

# ╔═╡ 7b7bf6c0-8f53-4b20-9e72-7b050e497eb9
md"""
- `DataPipes.jl` can be plugged into vanilla Julia pipelines using the **`@f` macro** instead of `@p`:
"""

# ╔═╡ 43d4c901-5f64-41c9-9377-0532f6456745
[1, 2, 3, 4] |> @f(map(_^2)) |> sum

# ╔═╡ 0679c05d-c965-40d2-bf11-604c4f5670c5
md"""
- The **`@aside` flag** is convenient to compute intermediate results without breaking the pipeline:
"""

# ╔═╡ 344c16cc-8657-477a-8c3a-f29d3fedd8f3
@p let
	data
	@aside avg = mean(_.age)
	map((; _.name, _.age, above_average=_.age > avg))
end

# ╔═╡ 6ee84e06-0639-40be-a539-d2cef51b1d6a
md"""
Note that the `avg` variable is local to the pipeline by default, and doesn't pollute the outer namespace:
"""

# ╔═╡ 85f252db-76c8-45f9-8c76-060d7d367579
@isdefined avg

# ╔═╡ 42c45873-f095-4bc6-925f-9067943c4949
md"""
- Intermediate results can be explicitly exported if needed using the **`@export` flag**:
"""

# ╔═╡ b5b55629-bdfe-4080-9620-50daadfa3aab
@p let
	data
	@aside @export avg_e = mean(_.age)
	map((; _.name, _.age, above_average=_.age > avg_e))
end

# ╔═╡ 7b759921-4122-4992-bc14-3e6d303b65a9
avg_e

# ╔═╡ d63abc7f-65eb-46dd-9d7f-47ed114a28c7
md"""
... or by putting the whole pipeline into a **`begin-end` block instead of `let-end`**:
"""

# ╔═╡ b4fb463a-6444-42f8-9a55-79189409c12a
@p begin
	data
	@aside avg_b = mean(_.age)
	map((; _.name, _.age, above_average=_.age > avg_e))
end

# ╔═╡ 8b198214-e438-429e-ab6b-f192a97533ba
avg_b

# ╔═╡ 0f60c871-6fee-44e9-a6fe-b25aa5d7429b
md"""
## Advanced
"""

# ╔═╡ 2bb136a9-ea90-4a11-a56f-f52aebb47d9e
md"""
_Features described in this section are very rarely needed and can be safely ignored._
"""

# ╔═╡ 59ce4283-ffdb-4f2c-814c-8c81243d558d


# ╔═╡ 72c722de-e03a-4a0f-90b0-3f896e32c778
md"""
`DataPipes.jl` exports both full and abbreviated forms of its macros: `@pipe === @p`, `@pipefunc === @f`. Full forms alone can be loaded with `using DataPipes.NoAbbr` instead of `using DataPipes`.
"""

# ╔═╡ 1083b8f8-8830-45c9-b15c-47d884affb42


# ╔═╡ 57e5cb80-1211-4301-8786-b70c0a71d49a
md"""
In nested pipes, use the **`_ꜛ` placeholder** to refer to the `_` argument of the outer pipe _(the arrow can be typed with `\^uparrow`)_:
"""

# ╔═╡ 3410d91b-a6ab-4f4d-9121-589d21dd2dcb
@p let
	data
	map() do _
		@p _ꜛ.measurements |> map((;_.weight, weight_over_age=_.weight / _ꜛ.age))
	end
end

# ╔═╡ 83664d95-6d1c-4657-b4b5-5cd15134c617


# ╔═╡ a13397e2-f91f-4424-8ee2-c1f52f9e3e83
md"""
In rare cases, the result of the previous step is not needed at all. The **`@_` flag** disables its insertion.
Here is an example, but note that the same result is cleaner with the `@aside` flag explained above:
"""

# ╔═╡ c4ca6f3e-430f-4d49-abfb-cbc443c7aba2
@p let
	data
	avg = mean(_.age)
	@_ map((; _.name, _.age, above_average=_.age > avg), data)
end

# ╔═╡ 3dd966df-9a17-41c4-857f-02b8f141933b


# ╔═╡ 3e1dbda9-6e7c-47ed-9be1-568dbef9f783
md"""
When a step should be kept as-is without any modifications by `DataPipes.jl`, use the **`@asis` flag**. This is not supposed to be generally useful, but is possible:
"""

# ╔═╡ f184dc38-2322-412e-af21-086ec183fa2c
@p let
	a = [1, 2, 3, 4]
	@asis map(x -> x^2, a)
	filter(exp(_) > 5)
end

# ╔═╡ 62e7866f-ebf0-4a3f-b683-2d6eb80a3723


# ╔═╡ 8aec6497-474c-4919-acb6-641499343ed4


# ╔═╡ 8cfd98d0-1b4b-4938-a3f3-912fa5d655cd
md"""
Only notebook setup below
"""

# ╔═╡ 7e3753a8-fcb0-4a13-bfaa-df9a54ebab56
TableOfContents()

# ╔═╡ 02cb5e5c-94d7-4fc3-bd4a-8cbab448472f
_CK = HTML("""<input type=checkbox checked onclick="return false">""")

# ╔═╡ 52316082-aee8-44d4-b18b-64ec0588332c
md"""
There are multiple implementation of the piping concept in Julia: [1](https://github.com/c42f/Underscores.jl), [2](https://github.com/jkrumbiegel/Chain.jl), [3](https://github.com/FNj/Hose.jl), [4](https://github.com/oxinabox/Pipe.jl), maybe even more. `DataPipes` design is focused on usual data processing and analysis tasks. What makes `DataPipes` distinct from other packages is that it ticks all these points:

 $_CK Gets rid of basically all boilerplate for common data processing functions:
```julia
@p tbl |> filter(_.a > 5) |> map(_.b + _.c)
```
 $_CK Can be inserted in as a step of a vanilla Julia pipeline without modifying the latter:
```julia
tbl |> sum  # before
tbl |> @f(map(_ ^ 2) |> filter(_ > 5)) |> sum  # after
```
 $_CK Can define a function transforming the data instead of immediately applying it
```julia
func = @f map(_ ^ 2) |> filter(_ > 5) |> sum  # define func
func(tbl)  # apply it
```
 $_CK Supports easily exporting the result of an intermediate pipeline step
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
 $_CK Provides no-boilerplate nesting
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
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
DataPipes = "02685ad9-2d12-40c3-9f73-c6aeda6a7ff5"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
SplitApplyCombine = "03a91e81-4c3e-53e1-a0a4-9c0c8f19dd66"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[compat]
DataPipes = "~0.3.0"
PlutoUI = "~0.7.40"
SplitApplyCombine = "~1.2.2"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.8.0"
manifest_format = "2.0"
project_hash = "ceecdca4cea769cb0cd2c398f90782b0b070199a"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "0.5.2+0"

[[deps.DataPipes]]
git-tree-sha1 = "f1e3d1a1d834a1c5f4977fbebe537b1cab0e8b18"
uuid = "02685ad9-2d12-40c3-9f73-c6aeda6a7ff5"
version = "0.3.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.Dictionaries]]
deps = ["Indexing", "Random", "Serialization"]
git-tree-sha1 = "96dc5c5c8994be519ee3420953c931c55657a3f2"
uuid = "85a47980-9c8c-11e8-2b9f-f7ca1fa99fb4"
version = "0.3.24"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[deps.Indexing]]
git-tree-sha1 = "ce1566720fd6b19ff3411404d4b977acd4814f9f"
uuid = "313cdc1a-70c2-5d6a-ae34-0150d3930a38"
version = "1.1.1"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[deps.Parsers]]
deps = ["Dates"]
git-tree-sha1 = "3d5bf43e3e8b412656404ed9466f1dcbf7c50269"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.4.0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "a602d7b0babfca89005da04d89223b867b55319f"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.40"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SplitApplyCombine]]
deps = ["Dictionaries", "Indexing"]
git-tree-sha1 = "48f393b0231516850e39f6c756970e7ca8b77045"
uuid = "03a91e81-4c3e-53e1-a0a4-9c0c8f19dd66"
version = "1.2.2"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.Tricks]]
git-tree-sha1 = "6bac775f2d42a611cdfcd1fb217ee719630c4175"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.6"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─c310bae2-624c-48f9-af30-5a6367ed61c9
# ╟─d7f69973-d32f-410d-827c-2c279d8f3f74
# ╟─52316082-aee8-44d4-b18b-64ec0588332c
# ╟─204b665f-c217-49ac-8d39-0f539bb880af
# ╟─f2db737b-da1e-4f89-a848-11a7a5362a21
# ╟─6ca26c7b-4adb-4787-bb9e-a9ff22d31bd2
# ╠═d5b99750-9b2a-427c-9615-3d41f13b41a2
# ╟─2eb9cbc9-3344-48f2-805a-b76a167604a1
# ╠═30713956-bcc3-4340-871a-04a990a13d57
# ╟─c60870e4-e44c-4608-8f0e-09958b947c07
# ╠═6dd43f36-8362-4cb2-83f9-e6ee9570a103
# ╟─d0c1feb0-e947-4067-add3-06f4bb32d5df
# ╠═321603ae-5dbb-4937-8483-17f1ea7e492e
# ╠═ed5afdd6-db6b-4e03-9ff6-738fd64186ab
# ╟─bed56650-1255-46c8-b797-453b3070faa3
# ╠═c98807a7-fdef-4f77-bc42-7fe6281a2ab1
# ╠═c2b7d864-f8b4-42c3-adaa-a4e900d5c387
# ╠═3a3425c4-17ba-41f2-86ec-fab349820591
# ╟─5f5a9d3b-5ced-4619-bfde-551cbbb041c8
# ╠═1920226f-85cf-4e8f-b72c-8a36b50e624f
# ╟─6016fdbb-1622-4826-9a00-adb6cdc42274
# ╠═0553e1a5-369f-4cee-b8b9-048ffc950f75
# ╟─5e8cbdd9-31d7-410a-8bb5-e6177db7eba7
# ╟─17cc402f-8b25-4f23-ac08-d6e8290ec0f7
# ╟─8ffd15fe-9576-4e51-b44e-6fb6b8e96103
# ╟─c9f60e22-a44d-4d40-ae7f-1a7354ec9842
# ╟─fe93fe81-05c8-4715-8ee8-6c61651b0f70
# ╠═959705f3-36ad-4a0e-8e59-8b62ab2c21b3
# ╟─c073fa33-7911-464e-98fc-9c76d603b2fb
# ╠═fe60a93a-2e86-43e5-ad35-b854fc522db6
# ╟─39f6423b-2846-4a85-9047-d937c11b46ec
# ╠═91dbd9a0-7bbe-44d2-8e46-bf9f38a83b85
# ╟─6aee48a0-344d-4777-bec2-6cd077f29a69
# ╠═0a2921d0-f7eb-4eeb-a58b-6a658668aee3
# ╠═18a06b16-632d-4b42-8ca8-db72993d7eca
# ╟─bf441014-7f2f-4811-9641-5b83fd501ffc
# ╠═fdde50d3-0527-4914-affd-2a2d2071a922
# ╟─af92d4a9-a683-4ce7-b714-0aa63646b235
# ╠═0390197f-8444-497c-ab54-5d2740594d04
# ╟─44ab9fc7-0d22-444e-b92b-9c95341a71f0
# ╟─af10d9dc-6005-4c99-909f-e68cbd1292eb
# ╠═543fd79d-596f-4147-924d-99601431f2b7
# ╟─7b7bf6c0-8f53-4b20-9e72-7b050e497eb9
# ╠═43d4c901-5f64-41c9-9377-0532f6456745
# ╟─0679c05d-c965-40d2-bf11-604c4f5670c5
# ╠═344c16cc-8657-477a-8c3a-f29d3fedd8f3
# ╟─6ee84e06-0639-40be-a539-d2cef51b1d6a
# ╠═85f252db-76c8-45f9-8c76-060d7d367579
# ╟─42c45873-f095-4bc6-925f-9067943c4949
# ╠═b5b55629-bdfe-4080-9620-50daadfa3aab
# ╠═7b759921-4122-4992-bc14-3e6d303b65a9
# ╟─d63abc7f-65eb-46dd-9d7f-47ed114a28c7
# ╠═b4fb463a-6444-42f8-9a55-79189409c12a
# ╠═8b198214-e438-429e-ab6b-f192a97533ba
# ╟─0f60c871-6fee-44e9-a6fe-b25aa5d7429b
# ╟─2bb136a9-ea90-4a11-a56f-f52aebb47d9e
# ╠═59ce4283-ffdb-4f2c-814c-8c81243d558d
# ╟─72c722de-e03a-4a0f-90b0-3f896e32c778
# ╠═1083b8f8-8830-45c9-b15c-47d884affb42
# ╟─57e5cb80-1211-4301-8786-b70c0a71d49a
# ╠═3410d91b-a6ab-4f4d-9121-589d21dd2dcb
# ╠═83664d95-6d1c-4657-b4b5-5cd15134c617
# ╟─a13397e2-f91f-4424-8ee2-c1f52f9e3e83
# ╠═c4ca6f3e-430f-4d49-abfb-cbc443c7aba2
# ╠═3dd966df-9a17-41c4-857f-02b8f141933b
# ╟─3e1dbda9-6e7c-47ed-9be1-568dbef9f783
# ╠═f184dc38-2322-412e-af21-086ec183fa2c
# ╠═62e7866f-ebf0-4a3f-b683-2d6eb80a3723
# ╠═8aec6497-474c-4919-acb6-641499343ed4
# ╟─8cfd98d0-1b4b-4938-a3f3-912fa5d655cd
# ╠═586750fc-5b72-11ec-3858-6dfbd4edb6d9
# ╠═bb7c0cbf-2012-4f78-bf6c-ff918d729b75
# ╠═c5015ff8-cb95-4776-bcfd-a0203d2089cf
# ╠═2c793094-964f-4f50-8c12-6c5cd30b7228
# ╠═7e3753a8-fcb0-4a13-bfaa-df9a54ebab56
# ╠═02cb5e5c-94d7-4fc3-bd4a-8cbab448472f
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
