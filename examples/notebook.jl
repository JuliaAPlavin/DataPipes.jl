### A Pluto.jl notebook ###
# v0.17.1

using Markdown
using InteractiveUtils

# ╔═╡ 586750fc-5b72-11ec-3858-6dfbd4edb6d9
using DataPipes

# ╔═╡ bb7c0cbf-2012-4f78-bf6c-ff918d729b75
using SplitApplyCombine

# ╔═╡ c5015ff8-cb95-4776-bcfd-a0203d2089cf
using Statistics

# ╔═╡ 334c70c1-2414-4d66-9667-c3805259d97a


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

# ╔═╡ e12d5b88-84df-4274-b605-2e52ee307839


# ╔═╡ 2eb9cbc9-3344-48f2-805a-b76a167604a1
md"""
Simple data manipulation using Julia Base functions become cleaner with `DataPipes.jl`:
"""

# ╔═╡ 30713956-bcc3-4340-871a-04a990a13d57
@p begin
	data
	filter(_.age > 30)
	map((;
		_.name,
		is_old=_.age > 70,
		have_many=length(_.measurements) > 10
	))
end

# ╔═╡ f7f28f9a-8480-452b-9884-06a70a25b99d


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
@p begin
	data
	map((;
		_.name,
		result=process_measurements(_.measurements),
	))
end

# ╔═╡ bed56650-1255-46c8-b797-453b3070faa3
md"""
Of course, this works with other packages as well. A notable example is `SplitApplyCombine.jl` that contains essential data processing functions like `group` and `join`:
"""

# ╔═╡ c98807a7-fdef-4f77-bc42-7fe6281a2ab1
d = @p begin
	data
	group((is_old=_.age > 30,))
	map(length)
end

# ╔═╡ c2b7d864-f8b4-42c3-adaa-a4e900d5c387
d[(is_old=true,)]

# ╔═╡ 3a3425c4-17ba-41f2-86ec-fab349820591


# ╔═╡ 5f5a9d3b-5ced-4619-bfde-551cbbb041c8
md"""
`DataPipes.jl` pipes can be cleanly nested:
"""

# ╔═╡ 1920226f-85cf-4e8f-b72c-8a36b50e624f
@p begin
	data
	map() do r
		(; r.name, cnts = @p r.measurements |> groupcount(_.mood))
	end
end

# ╔═╡ f42e502d-4fe8-47d8-8a10-eead8806c231


# ╔═╡ b31f0448-6cad-4f48-824c-5f398a677172
md"""
Let's illustrate multi-argument functions using joins as an example. First, create a secondary dataset:
"""

# ╔═╡ ea23c18a-6f54-44b8-b4eb-e6b79ec83544
data_letters = [
	(letter='A', value=1),
	(letter='B', value=2),
	(letter='C', value=3),
]

# ╔═╡ bfe51cde-2c46-4f9d-b1d0-080319a31104
md"""
Join it with the `data` defined above, using the first letter of names `_.name[1]` and `_.letter` as corresponding keys:
"""

# ╔═╡ ad7339d1-82c7-4662-96ea-f552af4e47e5
@p innerjoin(
	_.name[1], _.letter,
	(; _1.name, _1.age, letter_value=_2.value),
	data, data_letters
)

# ╔═╡ 8d535ea3-ad3e-46bf-b3a0-fe8a9c114247


# ╔═╡ 17cc402f-8b25-4f23-ac08-d6e8290ec0f7
md"""
# `DataPipes.jl` details
"""

# ╔═╡ 8ffd15fe-9576-4e51-b44e-6fb6b8e96103
md"""
## Basic
"""

# ╔═╡ c9f60e22-a44d-4d40-ae7f-1a7354ec9842
md"""
The main interface of `DataPipes.jl` is the `@p` macro. It signifies the pipeline context where all transformations happen.
"""

# ╔═╡ cc774210-9b69-476b-bfe4-7ece7483ce81


# ╔═╡ fe93fe81-05c8-4715-8ee8-6c61651b0f70
md"""
Short pipelines can be written in a single line:
"""

# ╔═╡ 959705f3-36ad-4a0e-8e59-8b62ab2c21b3
@p data |> filter(_.age > 40) |> map(_.name)

# ╔═╡ c073fa33-7911-464e-98fc-9c76d603b2fb
md"""
The `begin-end` form is completely equivalent, and tends to be more convenient for longer sequences:
"""

# ╔═╡ fe60a93a-2e86-43e5-ad35-b854fc522db6
@p begin
	data
	filter(_.age > 40)
	map(_.name)
end

# ╔═╡ 39fb4ecf-4692-4b91-9870-a103a0f797c1


# ╔═╡ 39f6423b-2846-4a85-9047-d937c11b46ec
md"""
`DataPipes.jl` inserts the result of the previous pipeline step as the last function argument by default. This is convenient for common data manipulation functions following Julia conventions - as shown above.

However, it is easy to put the previous result anywhere in the expression manually using `__` (double underscore):
"""

# ╔═╡ 91dbd9a0-7bbe-44d2-8e46-bf9f38a83b85
@p begin
	"Hello World !"

	split(__, ' ')
	join(__, "! ")
end

# ╔═╡ 15db6118-5c36-4771-b08b-115a13c0497f


# ╔═╡ 6aee48a0-344d-4777-bec2-6cd077f29a69
md"""
Another code modification done by `DataPipes.jl` is replacing `_` placeholders with anonymous function ("lambdas") arguments. That is, `map(_.a + 1)` with `@p` is equivalent to `map(x -> x.a + 1)`.

Multivariate lambdas are supported through `_1`, `_2`, `_3`, ... syntax:
"""

# ╔═╡ 0a2921d0-f7eb-4eeb-a58b-6a658668aee3
@p map(_ + _2, 1:3, 10:12)

# ╔═╡ 18a06b16-632d-4b42-8ca8-db72993d7eca
@p map(_1 + _2, 1:3, 10:12)

# ╔═╡ e3d7d38d-9eda-42da-9113-1808376e02fc
@p innerjoin(length(_.name), length(_), (a=_.name, b=_2), data, ["", "A", "DEF", "B"])

# ╔═╡ bf441014-7f2f-4811-9641-5b83fd501ffc
md"""
Anonymous functions are supported in keyword arguments as well:
"""

# ╔═╡ fdde50d3-0527-4914-affd-2a2d2071a922
@p data |> sort(by=_.age) |> map(_.age)

# ╔═╡ 03875382-43f5-4f7f-a4d4-64b22dd3039c


# ╔═╡ af92d4a9-a683-4ce7-b714-0aa63646b235
md"""
The Julia `do`-notation is fully supported and convenient for complex functions. The argument can stay anonymous (`_`) or be named, but its name should be explicitly written either way to prevent confusion:
"""

# ╔═╡ 0390197f-8444-497c-ab54-5d2740594d04
@p begin
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

# ╔═╡ 3ed2d003-ee66-4a3d-9b85-c0bc2b4e4cdb


# ╔═╡ 44ab9fc7-0d22-444e-b92b-9c95341a71f0
md"""
## Intermediate
"""

# ╔═╡ 7b7bf6c0-8f53-4b20-9e72-7b050e497eb9
md"""
`DataPipes.jl` can be plugged into vanilla Julia pipelines using the `@f` macro instead of `@p`:
"""

# ╔═╡ 43d4c901-5f64-41c9-9377-0532f6456745
[1, 2, 3, 4] |> @f(map(_^2)) |> sum

# ╔═╡ b23a7512-97a5-4d3a-b04c-9595233f46bb


# ╔═╡ 0679c05d-c965-40d2-bf11-604c4f5670c5
md"""
The `@aside` macro is convenient to compute intermediate results without breaking the pipeline:
"""

# ╔═╡ 344c16cc-8657-477a-8c3a-f29d3fedd8f3
@p begin
	data
	@aside avg = mean(_.age)
	map((; _.name, _.age, above_average=_.age > avg))
end

# ╔═╡ 6ee84e06-0639-40be-a539-d2cef51b1d6a
md"""
Note that the `avg` variable is local to the pipeline, and doesn't pollute the outer namespace:
"""

# ╔═╡ 85f252db-76c8-45f9-8c76-060d7d367579
avg

# ╔═╡ 42c45873-f095-4bc6-925f-9067943c4949
md"""
Intermediate variables and final results can be explicitly exported if needed: use `@export` macro:
"""

# ╔═╡ b5b55629-bdfe-4080-9620-50daadfa3aab
@p begin
	data
	@aside @export avg_e = mean(_.age)
	@export result_e = map((; _.name, _.age, above_average=_.age > avg_e))
end

# ╔═╡ 7b759921-4122-4992-bc14-3e6d303b65a9
avg_e

# ╔═╡ b4fb463a-6444-42f8-9a55-79189409c12a
result_e

# ╔═╡ 3d90dcc2-3de4-4e4b-b968-2c3c7dab2f9c


# ╔═╡ 0f60c871-6fee-44e9-a6fe-b25aa5d7429b
md"""
## Advanced
"""

# ╔═╡ 72c722de-e03a-4a0f-90b0-3f896e32c778
md"""
`DataPipes.jl` exports both full and abbreviated forms of its macros: `@pipe === @p`, `@pipefunc === @f`. Full forms alone can be loaded with `using DataPipes.NoAbbr` instead of `using DataPipes`.
"""

# ╔═╡ 1083b8f8-8830-45c9-b15c-47d884affb42


# ╔═╡ 57e5cb80-1211-4301-8786-b70c0a71d49a
md"""
Pipes (`@p`) can be nested. Use `_ꜛ` to refer to the "anonymous" argument `_` of the outer pipe in this case (the arrow can be typed with `\^uparrow`):
"""

# ╔═╡ 3410d91b-a6ab-4f4d-9121-589d21dd2dcb
@p begin
	data
	map() do _
		@p _ꜛ.measurements |> map((;_.weight, weight_over_age=_.weight / _ꜛ.age))
	end
end

# ╔═╡ af10d9dc-6005-4c99-909f-e68cbd1292eb
md"""
Lambda functions consisting only of inner pipes is a common nesting pattern, especially with the `map` function. It has a more succint implicit syntax in `DataPipes`: the lambda function body is treated as an inner `@p` pipe when the only argument is `__` (double underscore). The intuition is that `__` refers to the previous pipeline step, and assigning to `__` we effectively start a new pipe.\
Here is a simple string-to-namedtuple parsing example using this feature:
"""

# ╔═╡ 543fd79d-596f-4147-924d-99601431f2b7
@p begin
	"a=1 b=2 c=3"

	split
	map() do __
		split(__, '=')
		Symbol(__[1]) => parse(Int, __[2])
	end
	NamedTuple
end

# ╔═╡ 83664d95-6d1c-4657-b4b5-5cd15134c617


# ╔═╡ a13397e2-f91f-4424-8ee2-c1f52f9e3e83
md"""
Sometimes the previous result is not needed at all: decorate such steps with the `@_` macro.
Here is an example, but note that the same result is cleaner with `@aside` (above):
"""

# ╔═╡ c4ca6f3e-430f-4d49-abfb-cbc443c7aba2
@p begin
	data
	avg = mean(_.age)
	@_ map((; _.name, _.age, above_average=_.age > avg), data)
end

# ╔═╡ ed1f4d37-fe95-42b1-bc66-f4a1db0731b8


# ╔═╡ 3e1dbda9-6e7c-47ed-9be1-568dbef9f783
md"""
When a step should be kept as-is without any modifications by `DataPipes.jl`, use `@asis` macro. This is not supposed to be generally useful, but is possible:
"""

# ╔═╡ f184dc38-2322-412e-af21-086ec183fa2c
@p begin
	a = [1, 2, 3, 4]
	@asis map(x -> x^2, a)
	filter(exp(_) > 5)
end

# ╔═╡ 865fa66f-0959-4089-8906-89d978ee23bf


# ╔═╡ 3a44fc7a-3c47-4ccc-a320-ba5b89c51931
md"""
# Experimental
"""

# ╔═╡ 41591295-ee32-4c0f-8804-a4235ff5a539
md"""
In addition to the pipe macro, `DataPipes.jl` contains several short functions for more convenient data processing. I didn't find a better place to put them for now, but they may be removed from this package at some point (only in a semver-breaking version).\
Note: some of these functions constitute type piracy.
"""

# ╔═╡ ba497bb7-354f-41ec-9d73-997a15bede76
md"""
- Callable symbols:
"""

# ╔═╡ 11033a42-d9cc-4cfa-b41d-fe85f74e43d4
nt = (a=123, b=234, c=345)

# ╔═╡ b6cc1cfe-dff3-42d8-ab79-0ef2276b6a53
:b(nt)

# ╔═╡ e84646d5-9374-4687-ae27-7f3d3e41b07f
@p data |> map(mean(:weight.(_.measurements)))

# ╔═╡ f8e2e4b1-d5f4-47a7-9539-70b29d852596


# ╔═╡ 27d108b9-5537-40ce-aee5-e072f4f39b32
md"""
- Extension of `SplitApplyCombine.mapmany` that accepts the second function argument. Analogue of C# `SelectMany`.
"""

# ╔═╡ 4dad2df7-a26f-41b8-b0d4-873cecc55b9c
@p data |> mapmany(_.measurements, (;_1.name, _2.weight))

# ╔═╡ a3173ff3-c05a-4747-b316-04aafada87af


# ╔═╡ 006eba40-b020-4d97-b9ef-2bbc80dcf151
md"""
- `filtermap` function to perform a filtering and mapping together. Analogue of Rust `filter_map`.
"""

# ╔═╡ 1be5c685-f21c-4416-a35d-c55ae68b2442
filtermap(-10:10) do x
	x < 0 && return nothing
	sqrt(x)
end

# ╔═╡ 2c8c328c-a87c-4d34-b69e-1f464f3a1eb4


# ╔═╡ 2acb6311-1018-478d-b233-9fc796f21b19
md"""
- A family of `mutate` functions: name taken from `R`. They add new fields to table-like strucures.
"""

# ╔═╡ 5c4a12d5-ef0c-4413-9a96-0baef0d51c28
md"""
Simple `mutate`:
"""

# ╔═╡ d4f2b862-b882-43bc-baaa-882ddfef568f
@p data |> mutate(is_old = _.age > 60)

# ╔═╡ f4dfea94-8725-4dde-9244-fc3d0f31f357
md"""
is equivalent to
"""

# ╔═╡ c494b026-b560-460a-8a98-3aa3307f84aa
@p data |> map((; _..., is_old = _.age > 60))

# ╔═╡ d756540a-96da-48a2-bc59-1d15f3a91aaa
md"""
`mutate_seq` allows using values of previously defined fields:
"""

# ╔═╡ b04745c5-502c-40b4-86a4-d936633c27ba
@p data |> mutate_seq(cnt = length(_.measurements), has_many = _.cnt > 4)

# ╔═╡ f9eb458b-e0ff-4250-9608-f2ecfa0ce7a7
md"""
`mutate_rec` merged `NamedTuple`s recursively:
"""

# ╔═╡ b71d8f78-f6d4-4e02-af83-b4e371e28043
tmp = [(a=1, b=(c=2, d=3)), (a=10, b=(c=20, d=30))]

# ╔═╡ 8d52fac3-3c1e-481c-9dde-aa05209b05e4
@p tmp |> mutate_rec((;b=(x=_.b.c^2,)))

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
DataPipes = "02685ad9-2d12-40c3-9f73-c6aeda6a7ff5"
SplitApplyCombine = "03a91e81-4c3e-53e1-a0a4-9c0c8f19dd66"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[compat]
DataPipes = "~0.2.1"
SplitApplyCombine = "~1.2.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.7.0-rc2"
manifest_format = "2.0"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[deps.DataPipes]]
deps = ["SplitApplyCombine"]
git-tree-sha1 = "4313a8b8e2cdac8745d871def86416da78b8629c"
uuid = "02685ad9-2d12-40c3-9f73-c6aeda6a7ff5"
version = "0.2.1"

[[deps.Dictionaries]]
deps = ["Indexing", "Random"]
git-tree-sha1 = "8b8de80c4584f8525239555c95955295075beb5b"
uuid = "85a47980-9c8c-11e8-2b9f-f7ca1fa99fb4"
version = "0.3.16"

[[deps.Indexing]]
git-tree-sha1 = "ce1566720fd6b19ff3411404d4b977acd4814f9f"
uuid = "313cdc1a-70c2-5d6a-ae34-0150d3930a38"
version = "1.1.1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SplitApplyCombine]]
deps = ["Dictionaries", "Indexing"]
git-tree-sha1 = "dec0812af1547a54105b4a6615f341377da92de6"
uuid = "03a91e81-4c3e-53e1-a0a4-9c0c8f19dd66"
version = "1.2.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
"""

# ╔═╡ Cell order:
# ╠═586750fc-5b72-11ec-3858-6dfbd4edb6d9
# ╠═bb7c0cbf-2012-4f78-bf6c-ff918d729b75
# ╠═c5015ff8-cb95-4776-bcfd-a0203d2089cf
# ╠═334c70c1-2414-4d66-9667-c3805259d97a
# ╟─f2db737b-da1e-4f89-a848-11a7a5362a21
# ╟─6ca26c7b-4adb-4787-bb9e-a9ff22d31bd2
# ╠═d5b99750-9b2a-427c-9615-3d41f13b41a2
# ╠═e12d5b88-84df-4274-b605-2e52ee307839
# ╟─2eb9cbc9-3344-48f2-805a-b76a167604a1
# ╠═30713956-bcc3-4340-871a-04a990a13d57
# ╠═f7f28f9a-8480-452b-9884-06a70a25b99d
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
# ╠═f42e502d-4fe8-47d8-8a10-eead8806c231
# ╟─b31f0448-6cad-4f48-824c-5f398a677172
# ╠═ea23c18a-6f54-44b8-b4eb-e6b79ec83544
# ╟─bfe51cde-2c46-4f9d-b1d0-080319a31104
# ╠═ad7339d1-82c7-4662-96ea-f552af4e47e5
# ╠═8d535ea3-ad3e-46bf-b3a0-fe8a9c114247
# ╟─17cc402f-8b25-4f23-ac08-d6e8290ec0f7
# ╟─8ffd15fe-9576-4e51-b44e-6fb6b8e96103
# ╟─c9f60e22-a44d-4d40-ae7f-1a7354ec9842
# ╠═cc774210-9b69-476b-bfe4-7ece7483ce81
# ╟─fe93fe81-05c8-4715-8ee8-6c61651b0f70
# ╠═959705f3-36ad-4a0e-8e59-8b62ab2c21b3
# ╟─c073fa33-7911-464e-98fc-9c76d603b2fb
# ╠═fe60a93a-2e86-43e5-ad35-b854fc522db6
# ╠═39fb4ecf-4692-4b91-9870-a103a0f797c1
# ╟─39f6423b-2846-4a85-9047-d937c11b46ec
# ╠═91dbd9a0-7bbe-44d2-8e46-bf9f38a83b85
# ╠═15db6118-5c36-4771-b08b-115a13c0497f
# ╟─6aee48a0-344d-4777-bec2-6cd077f29a69
# ╠═0a2921d0-f7eb-4eeb-a58b-6a658668aee3
# ╠═18a06b16-632d-4b42-8ca8-db72993d7eca
# ╠═e3d7d38d-9eda-42da-9113-1808376e02fc
# ╟─bf441014-7f2f-4811-9641-5b83fd501ffc
# ╠═fdde50d3-0527-4914-affd-2a2d2071a922
# ╠═03875382-43f5-4f7f-a4d4-64b22dd3039c
# ╟─af92d4a9-a683-4ce7-b714-0aa63646b235
# ╠═0390197f-8444-497c-ab54-5d2740594d04
# ╠═3ed2d003-ee66-4a3d-9b85-c0bc2b4e4cdb
# ╟─44ab9fc7-0d22-444e-b92b-9c95341a71f0
# ╟─7b7bf6c0-8f53-4b20-9e72-7b050e497eb9
# ╠═43d4c901-5f64-41c9-9377-0532f6456745
# ╠═b23a7512-97a5-4d3a-b04c-9595233f46bb
# ╟─0679c05d-c965-40d2-bf11-604c4f5670c5
# ╠═344c16cc-8657-477a-8c3a-f29d3fedd8f3
# ╟─6ee84e06-0639-40be-a539-d2cef51b1d6a
# ╠═85f252db-76c8-45f9-8c76-060d7d367579
# ╟─42c45873-f095-4bc6-925f-9067943c4949
# ╠═b5b55629-bdfe-4080-9620-50daadfa3aab
# ╠═7b759921-4122-4992-bc14-3e6d303b65a9
# ╠═b4fb463a-6444-42f8-9a55-79189409c12a
# ╠═3d90dcc2-3de4-4e4b-b968-2c3c7dab2f9c
# ╟─0f60c871-6fee-44e9-a6fe-b25aa5d7429b
# ╟─72c722de-e03a-4a0f-90b0-3f896e32c778
# ╠═1083b8f8-8830-45c9-b15c-47d884affb42
# ╟─57e5cb80-1211-4301-8786-b70c0a71d49a
# ╠═3410d91b-a6ab-4f4d-9121-589d21dd2dcb
# ╟─af10d9dc-6005-4c99-909f-e68cbd1292eb
# ╠═543fd79d-596f-4147-924d-99601431f2b7
# ╠═83664d95-6d1c-4657-b4b5-5cd15134c617
# ╟─a13397e2-f91f-4424-8ee2-c1f52f9e3e83
# ╠═c4ca6f3e-430f-4d49-abfb-cbc443c7aba2
# ╠═ed1f4d37-fe95-42b1-bc66-f4a1db0731b8
# ╟─3e1dbda9-6e7c-47ed-9be1-568dbef9f783
# ╠═f184dc38-2322-412e-af21-086ec183fa2c
# ╠═865fa66f-0959-4089-8906-89d978ee23bf
# ╟─3a44fc7a-3c47-4ccc-a320-ba5b89c51931
# ╟─41591295-ee32-4c0f-8804-a4235ff5a539
# ╟─ba497bb7-354f-41ec-9d73-997a15bede76
# ╠═11033a42-d9cc-4cfa-b41d-fe85f74e43d4
# ╠═b6cc1cfe-dff3-42d8-ab79-0ef2276b6a53
# ╠═e84646d5-9374-4687-ae27-7f3d3e41b07f
# ╠═f8e2e4b1-d5f4-47a7-9539-70b29d852596
# ╟─27d108b9-5537-40ce-aee5-e072f4f39b32
# ╠═4dad2df7-a26f-41b8-b0d4-873cecc55b9c
# ╠═a3173ff3-c05a-4747-b316-04aafada87af
# ╟─006eba40-b020-4d97-b9ef-2bbc80dcf151
# ╠═1be5c685-f21c-4416-a35d-c55ae68b2442
# ╠═2c8c328c-a87c-4d34-b69e-1f464f3a1eb4
# ╟─2acb6311-1018-478d-b233-9fc796f21b19
# ╟─5c4a12d5-ef0c-4413-9a96-0baef0d51c28
# ╠═d4f2b862-b882-43bc-baaa-882ddfef568f
# ╟─f4dfea94-8725-4dde-9244-fc3d0f31f357
# ╠═c494b026-b560-460a-8a98-3aa3307f84aa
# ╟─d756540a-96da-48a2-bc59-1d15f3a91aaa
# ╠═b04745c5-502c-40b4-86a4-d936633c27ba
# ╟─f9eb458b-e0ff-4250-9608-f2ecfa0ce7a7
# ╠═b71d8f78-f6d4-4e02-af83-b4e371e28043
# ╠═8d52fac3-3c1e-481c-9dde-aa05209b05e4
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
