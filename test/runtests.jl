using SplitApplyCombine
using DataPipes
using Test

module MyModule
myfunc(x) = 2x
end


@testset "data functions" begin
    @testset "callable symbols" begin
        x = (a=123, def="c")
        @test (:a)(x) == 123
        @test Val(:def)(x) == "c"
    end

    @testset "mapmany" begin
        X = [(a=[1, 2],), (a=[3, 4],)]
        # method from SAC.jl
        @test mapmany(x -> x.a, X) == [1, 2, 3, 4]
        # my method
        @test mapmany(x -> x.a, (x, a) -> (a, sum(x.a)), X) == [(1, 3), (2, 3), (3, 7), (4, 7)]
    end

    @testset "mutate" begin
        X = [(a=1, b=(c=2,)), (a=3, b=(c=4,))]
        @test mutate(x -> (c=x.a^2,), X) == [(a=1, b=(c=2,), c=1), (a=3, b=(c=4,), c=9)]
        @test mutate(x -> (a=x.a^2,), X) == [(a=1, b=(c=2,)), (a=9, b=(c=4,))]
        @test mutate(c=x -> x.a^2, X) == [(a=1, b=(c=2,), c=1), (a=3, b=(c=4,), c=9)]
        @test mutate(c=x -> x.a^2, d=x -> x.a + 1, X) == [(a=1, b=(c=2,), c=1, d=2), (a=3, b=(c=4,), c=9, d=4)]

        @test_throws ErrorException mutate(c=x -> x.a^2, d=x -> x.c + 1, X)
        @test mutate_seq(c=x -> x.a^2, d=x -> x.a + 1, X) == [(a=1, b=(c=2,), c=1, d=2), (a=3, b=(c=4,), c=9, d=4)]
        @test mutate_seq(c=x -> x.a^2, d=x -> x.c + 1, X) == [(a=1, b=(c=2,), c=1, d=2), (a=3, b=(c=4,), c=9, d=10)]

        @test mutate(x -> (b=(d=x.a,),), X) == [(a=1, b=(d=1,)), (a=3, b=(d=3,))]
        @test mutate_rec(x -> (b=(d=x.a,),), X) == [(a=1, b=(c=2, d=1)), (a=3, b=(c=4, d=3))]
        @test mutate_rec(x -> (b=(c=x.a,),), X) == [(a=1, b=(c=1,)), (a=3, b=(c=3,))]
    end

    @testset "filter_map" begin
        X = 1:10
        Y = filtermap(x -> x % 3 == 0 ? Some(x^2) : nothing, X)
        @test Y == [9, 36, 81]
        @test typeof(Y) == Vector{Int}

        @test filtermap(x -> x % 3 == 0 ? x^2 : nothing, X) == [9, 36, 81]
        @test filtermap(x -> x % 3 == 0 ? Some(nothing) : nothing, X) == [nothing, nothing, nothing]

        @test filtermap(x -> x % 3 == 0 ? Some(x^2) : nothing, (1, 2, 3, 4, 5, 6)) === (9, 36)
    end
end

@testset "pipe" begin
    data = [
        (name="A B", values=[1, 2, 3, 4]),
        (name="C", values=[5, 6]),
    ]
    data_original = copy(data)

    @testset "simple" begin
        @test @pipe(123) == 123
        @test @pipe(data) == data

        @test @pipe(data, map(_.name)) == ["A B", "C"]
        @test @p(data, map(_.name)) == ["A B", "C"]

        @test (@pipe begin
            data
            map(_.name)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map() do x
                x.name
            end
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map() do _
                _.name
            end
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map(_ -> _.name)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map(x -> x.name)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map(_ -> let
                _.name
            end)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map(x -> let
                x.name
            end)
        end) == ["A B", "C"]

        @test_broken (@pipe begin
            data
            map(function(_)
                _.name
            end)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            map(function(x)
                x.name
            end)
        end) == ["A B", "C"]

        @test_broken (@pipe begin
            data
            mutate(X=function(_)
                _.name
            end)
            map(_.X)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            mutate(X=function(x)
                x.name
            end)
            map(_.X)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            mutate(X=function(x)
                x.name * "_"
            end)
            map(_.X)
        end) == ["A B_", "C_"]

        @test (@pipe map(_.name, data)) == ["A B", "C"]

        @test_broken @p(1:4 |> Base.identity) == 1:4
        @test_broken @p("abc" |> Base.identity) == "abc"

        @test let
            f(x) = x^2
            @pipe begin
                data
                map(f(_.name))
            end
        end == ["A BA B", "CC"]

        @test (@pipe begin
            data
            map((;_.name))
        end) == [(name="A B",), (name="C",)]

        f = data -> @pipe begin
            data
            map((;_.name))
        end
        @test @inferred(f(data)) == [(name="A B",), (name="C",)]

        @test (@pipe begin
            data
            map(x -> (;x.name, values=123))
        end) == [
            (name="A B", values=123),
            (name="C", values=123),
        ]

        @test let
            x = (;values=1:3)
            @pipe(x.values |> map(_^2))
        end == [1, 4, 9]

        @test (@pipe begin
            data
            map("abc $(_.name)")
        end) == ["abc A B", "abc C"]

        @test @pipe(map(_ + __, 1:3, 10:12)) == [11, 13, 15]
        @test @pipe(map(_ + ___, 1:3, [nothing, nothing, nothing], 10:12)) == [11, 13, 15]

        @test (@pipe begin
            123
        end) == 123

        @test (@pipe begin
            123
            MyModule.myfunc()
        end) == 246

        @test (@pipe begin
            [123, 321]
            map(MyModule.myfunc)
        end) == [246, 642]

        @test (@p "abc") == "abc"
        @test (@p "abc" |> uppercase) == "ABC"
        @test (@p begin
            "abc"
        end) == "abc"
        @test_broken (@p begin
            "abc"
            uppercase()
        end) == "ABC"
        @test_broken (@p begin
            "abc"
            uppercase(↑)
        end) == "ABC"

        @test (@p begin
            1:3
            map(_, (↑) .* 10)
        end) == [10, 20, 30]
        @test (@p begin
            1:3
            map((↑) .* 10) do _
                _
            end
        end) == [10, 20, 30]
        @test (@p begin
            1:3
            map((↑) .* 10) do x
                x
            end
        end) == [10, 20, 30]
    end

    @testset "composable pipe" begin
        @test @pipe(begin
            data
            map(@pipe(_1))
        end) == [(name = "A B", values = [1, 2, 3, 4]), (name = "C", values = [5, 6])]
        @test @pipe(begin
            data
            map(@pipe(_1.name))
        end) == ["A B", "C"]

        @test @pipe(begin
            data
            map(@pipe(_1.name, collect, map(_^2), join(↑, "")))
        end) == ["AA  BB", "CC"]

        @test @pipe(begin
            data
            map(@pipe(_1.name, collect, map(lowercase(_)^2), join(↑, "")))
        end) == ["aa  bb", "cc"]

        @test_broken @pipe(begin
            data
            map(@pipe(_1.name, collect, map(@pipe(_1, string, lowercase, (↑)^2)), join(↑, "")))
        end) == ["aa  bb", "cc"]
    end

    @testset "pipe function" begin
        @test data |> @f(map(_.name)) == ["A B", "C"]
        @test data |> @f(map(_.name) |> map(_^2)) == ["A BA B", "CC"]
        @test @pipe(data) |> @f(map(_.name) |> map(_^2)) == ["A BA B", "CC"]
        @test @pipe(data, map(_.name)) |> @f(map(_^2)) == ["A BA B", "CC"]
    end

    @testset "nested pipes" begin
        @test (@pipe begin
            data
            map(x -> (;x.name, values=@pipe(x.values |> map(_^2))))
        end) == [
            (name="A B", values=[1, 4, 9, 16]),
            (name="C", values=[25, 36]),
        ]

        @test (@pipe begin
            data
            map((;_.name, values=@pipe(_1.values |> map(_^2))))
        end) == [
            (name="A B", values=[1, 4, 9, 16]),
            (name="C", values=[25, 36]),
        ]

        @test (@pipe begin
            data
            map((;_.name, values=@p(_1.values |> map(_^2))))
        end) == [
            (name="A B", values=[1, 4, 9, 16]),
            (name="C", values=[25, 36]),
        ]

        @test (@pipe begin
            data
            map((;_.name, values=@pipe(_1.values |> map(_^2) |> map((n=_1.name, v=_)))))
        end) == [
            (name="A B", values=[(n="A B", v=1), (n="A B", v=4), (n="A B", v=9), (n="A B", v=16)]),
            (name="C", values=[(n="C", v=25), (n="C", v=36)]),
        ]

        @test (@p begin
            data
            map((;_.name, values=_.values |> @f(map(_^2) |> map((n=_1.name, v=_)))))
        end) == [
            (name="A B", values=[(n="A B", v=1), (n="A B", v=4), (n="A B", v=9), (n="A B", v=16)]),
            (name="C", values=[(n="C", v=25), (n="C", v=36)]),
        ]

        @test (@p begin
            data
            map((;_.name, values=_.values |> @f(map(_^2))))
        end) == [
            (name="A B", values=[1, 4, 9, 16]),
            (name="C", values=[25, 36]),
        ]
    end

    @testset "other base funcs" begin
        @test (@pipe begin
            data
            filter(length(_.values) > 3)
        end) == [(name="A B", values=[1, 2, 3, 4])]

        @test (@pipe begin
            data
            map(_)
            filter!(length(_.values) > 3)
        end) == [(name="A B", values=[1, 2, 3, 4])]

        data_copy = copy(data)
        @test (@pipe begin
            data_copy
            filter!(length(_.values) > 3)
        end) == [(name="A B", values=[1, 2, 3, 4])]
        @test data_copy == [(name="A B", values=[1, 2, 3, 4])]

        @test (@pipe begin
            data
            sort(by=length(_.values))
        end) == [
            (name="C", values=[5, 6]),
            (name="A B", values=[1, 2, 3, 4]),
        ]

        @test (@pipe begin
            data
            sort(by=length(_.values), rev=true)
        end) == [
            (name="A B", values=[1, 2, 3, 4]),
            (name="C", values=[5, 6]),
        ]

        data_copy = copy(data)
        @test (@pipe begin
            data_copy
            sort!(by=length(_.values))
        end) == [
            (name="C", values=[5, 6]),
            (name="A B", values=[1, 2, 3, 4]),
        ]
        @test data_copy == [
            (name="C", values=[5, 6]),
            (name="A B", values=[1, 2, 3, 4]),
        ]
    end

    @testset "my funcs" begin
        @test (@pipe begin
            data
            mapmany(_.values, __)
        end) == [1, 2, 3, 4, 5, 6]

        @test (@pipe begin
            data
            mapmany(_.values, (; _.name, value=__^2))
        end) == [
            (name="A B", value=1), (name="A B", value=4), (name="A B", value=9), (name="A B", value=16),
            (name="C", value=25), (name="C", value=36)
        ]

        @test (@pipe begin
            data
            mutate((fname=split(_.name)[1],))
        end) == [
            (name="A B", values=[1, 2, 3, 4], fname="A"),
            (name="C", values=[5, 6], fname="C"),
        ]

        @test (@pipe begin
            data
            mutate(fname=split(_.name)[1])
        end) == [
            (name="A B", values=[1, 2, 3, 4], fname="A"),
            (name="C", values=[5, 6], fname="C"),
        ]

        @test @inferred(DataPipes.merge_iterative((;), a=x -> 1, b=x -> 2)) == (a=1, b=2)
        @test @inferred(DataPipes.merge_iterative((;), a=x -> x, b=x -> length(x))) == (a=(;), b=1)

        @test (@pipe begin
            data
            mutate_seq(fname=split(_.name)[1])
        end) == [
            (name="A B", values=[1, 2, 3, 4], fname="A"),
            (name="C", values=[5, 6], fname="C"),
        ]

        @test (@pipe begin
            data
            mutate_seq(parts=split(_.name), fname=_.parts[1])
            map(_.fname)
        end) == ["A", "C"]

        f = data -> @pipe begin
            data
            mutate_seq(parts=split(_.name), fname=_.parts[1])
            map(_.fname)
        end
        @test @inferred(f(data)) == ["A", "C"]

        @test @pipe(data, map(:name)) == ["A B", "C"]
        @test @pipe(data, map(Val(:name))) == ["A B", "C"]
        f = data -> @pipe(data, map(Val(:name)))
        @test @inferred(f(data)) == ["A B", "C"]

        @test @pipe([(a=1, b=(c=2, d=3))] |> mutate_rec((;b=_.a))) == [(a=1, b=1)]
        @test @pipe([(a=1, b=(c=2, d=3))] |> mutate_rec((;b=(;c=_.a)))) == [(a=1, b=(c=1, d=3))]
        @test @pipe([(a=1, b=(c=2, d=3))] |> mutate_rec((;b=(;x=_.a)))) == [(a=1, b=(c=2, d=3, x=1))]
        # @test_broken @pipe([(a=1, b=(c=2, d=3))] |> mutate(b.c=_.a))
    end

    @testset "SAC funcs" begin
        @test (@pipe begin
            data
            mapmany(_.values, __)
            group(_ % 2)
            pairs()
            collect()
        end) == [1 => [1, 3, 5], 0 => [2, 4, 6]]
        
        @test (@pipe begin
            data
            mapmany(_.values, __)
            SplitApplyCombine.group(_ % 2)
            pairs()
            collect()
        end) == [1 => [1, 3, 5], 0 => [2, 4, 6]]

        @test (@pipe begin
            data
            mapmany(_.values, __)
            group(_ % 2)
            map(_[end])
            pairs()
            collect()
        end) == [1 => 5, 0 => 6]

        @test (@pipe begin
            data
            mapview(_.name)
        end) == ["A B", "C"]

        @test (@pipe begin
            data
            product(_ + length(__.values), [0, 1, 2])
        end) == [4 2; 5 3; 6 4]

        @test (@pipe begin
            data
            mapmany(_.values, __)
            innerjoin(_ % 2, 1 - _ % 2, (_, __), 1:3)
            sort()
        end) == [(2, 1), (1, 2), (3, 2), (2, 3), (1, 4), (3, 4), (2, 5), (1, 6), (3, 6)] |> sort

        @test (@pipe begin
            data
            mapmany(_.values, __)
            innerjoin(_ % 2, 1 - _ % 2, (_, __), _ == __, 1:3)
            sort()
        end) == [(2, 1), (1, 2), (3, 2), (2, 3), (1, 4), (3, 4), (2, 5), (1, 6), (3, 6)] |> sort

        @test (@pipe begin
            data
            mapmany(_.values, __)
            innerjoin(identity, identity, (_, __), _ % 2 != __ % 2, 1:3)
            sort()
        end) == [(2, 1), (1, 2), (3, 2), (2, 3), (1, 4), (3, 4), (2, 5), (1, 6), (3, 6)] |> sort
    end

    @testset "explicit arg" begin
        @test (@pipe begin
            data
            first()
            first((↑).values)
        end) == 1

        @test (@pipe begin
            data
            first(first(↑).values)
        end) == 1

        @test (@pipe begin
            data
            ↑
        end) == data

        @test (@pipe begin
            data
            (↑)[1]
        end) == (name = "A B", values = [1, 2, 3, 4])

        @test (@pipe begin
            data
            (↑)[1].values[1]
        end) == 1
        
        @test (@pipe begin
            (1, 2, 3)
            NamedTuple{(:a, :b, :c)}()
        end) == (a=1, b=2, c=3)
        @test (@pipe begin
            (1, 2, 3)
            NamedTuple{(:a, :b, :c)}(↑)
        end) == (a=1, b=2, c=3)

        @test_throws MethodError (@pipe begin
            a = 1:5
            b = 6:10
        end)

        @test (@pipe begin
            a = 1:5
            @asis b = 6:10
        end) == 6:10

        @test (@pipe begin
            a = 1:5
            @asis b = 6:10
            @asis map((x, y) -> x + y, a, b)
        end) == [7, 9, 11, 13, 15]

        @test (@pipe begin
            a = 1:5
            @asis b = 6:10
            @_ map(_ + __, a, b)
        end) == [7, 9, 11, 13, 15]

        @test (@pipe begin
            a = 1:5
            @_ b = 6:10
            @_ map(_ + __, a, b)
        end) == [7, 9, 11, 13, 15]

        @test_throws MethodError (@pipe begin
            data
            map((; _.name, n=length(↑)))
        end)

        @test (@pipe begin
            data
            map((; _.name, n=length(↑)), ↑)
        end) == [(name = "A B", n = 2), (name = "C", n = 2)]

        @test (@pipe begin
            a = data
            @asis map(x -> length(x.values) > 3, a)
        end) == [true, false]

        let
            g(x) = length(x.values)
            @test (@pipe begin
                a = data
                @asis map(g, a)
            end) == [4, 2]
        end

        let
            h(x) = length(x)
            @test (@pipe begin
                @asis h(data)
            end) == 2
        end

        @test_throws ErrorException @eval(@pipe begin
            a = data
            @asis map(length(_.values) > 3, a)
        end)
    end

    @testset "assigments" begin
        @test (@pipe begin
            orig = [1, 2, 3, 4]
            map(_^2)
            filt = filter(_ >= 4)
            sum(↑) / sum(orig)
        end) == 2.9
        @test_throws UndefVarError orig
        @test_throws UndefVarError filt

        # XXX: not needed in reality; tests fail without this for some reason
        orig2 = orig3 = filt2 = val = ix = nothing

        @test (@pipe begin
            @export orig2 = [1, 2, 3, 4]
            map(_^2)
            filter(_ >= 4)
            sum(↑) / sum(orig2)
        end) == 2.9
        @test orig2 == [1, 2, 3, 4]

        @test (@pipe begin
            @export orig3 = [1, 2, 3, 4]
            map(_^2)
            @export filt2 = filter(_ >= 4)
            sum(↑) / sum(orig3)
        end) == 2.9
        @test orig3 == [1, 2, 3, 4]
        @test filt2 == [4, 9, 16]

        @test (@pipe begin
            [1, 2, 3, 4]
            map(_^2)
            val, ix = findmax()
            @asis val^2
        end) == 256
        @test val === nothing && ix === nothing

        @test (@pipe begin
            [1, 2, 3, 4]
            map(_^2)
            @export val, ix = findmax()
            @asis val^2
        end) == 256
        @test val == 16 && ix == 4

        # test that defining variables beforehand is not required; for some reason, only works in a function
        f = () -> begin
            r = @pipe begin
                [1, 2, 3, 4]
                map(_^2)
                @export val1, ix1 = findmax()
                @asis val1^2
            end
            return r, val1, ix1
        end
        @test f() == (256, 16, 4)
    end

    @testset "aside" begin
        @test (@p begin
            1:5
            map(_^2)
            @show 123
            map(_ + 1)
        end) == 124

        @test (@p begin
            1:5
            map(_^2)
            @aside @show 123
            map(_ + 1)
        end) == [2, 5, 10, 17, 26]

        @test (@p begin
            1:5
            map(_^2)
            @aside @show first(↑)
            map(_ + 1)
        end) == [2, 5, 10, 17, 26]

        x, y = nothing, nothing
        @test (@p begin
            1:5
            map(_^2)
            @aside @export x = last(↑)
            map(_ + 1)
        end) == [2, 5, 10, 17, 26]
        @test x == 25

        @test (@p begin
            1:5
            map(_^2)
            @aside @export y = last()
            map(_ + 1)
        end) == [2, 5, 10, 17, 26]
        @test y == 25

        @test (@p begin
            1:5
            map(_^2)
            @aside x = first()
            map(_ - x)
        end) == [0, 3, 8, 15, 24]

        @test (@p begin
            @aside x = 123
            1:5
            map(_^2)
            map(x - _)
        end) == [122, 119, 114, 107, 98]
    end

    @testset "errors" begin
        @test_throws UndefVarError @pipe begin
            data
            map((_, _1))
        end

        @test_throws UndefVarError @pipe begin
            data
            map((_, __2))
        end
    end

    @test data == data_original
end

using Documenter
doctest(DataPipes; manual=false)

import CompatHelperLocal
CompatHelperLocal.@check()
