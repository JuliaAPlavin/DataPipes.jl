using SplitApplyCombine
using DataPipes
using Test

import CompatHelperLocal
CompatHelperLocal.@check()

using Documenter
doctest(DataPipes; manual=false)


module MyModule
myfunc(x) = 2x
end


@testset begin
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

        @test (@pipe map(_.name, data)) == ["A B", "C"]

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
            map(@pipe(_1.name, collect, map(string(_)^2), join(↑, "")))
        end) == ["AA  BB", "CC"]

        @test_broken @pipe(begin
            data
            map(@pipe(_1.name, collect, map(@pipe(_1, string, _^2)), join(↑, "")))
        end) == ["AA  BB", "CC"]
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
            mutate_(fname=split(_.name)[1])
        end) == [
            (name="A B", values=[1, 2, 3, 4], fname="A"),
            (name="C", values=[5, 6], fname="C"),
        ]

        @test (@pipe begin
            data
            mutate_(parts=split(_.name), fname=_.parts[1])
            map(_.fname)
        end) == ["A", "C"]

        f = data -> @pipe begin
            data
            mutate_(parts=split(_.name), fname=_.parts[1])
            map(_.fname)
        end
        @test @inferred(f(data)) == ["A", "C"]

        @test @pipe(data, map(:name)) == ["A B", "C"]
        @test @pipe(data, map(Val(:name))) == ["A B", "C"]
        f = data -> @pipe(data, map(Val(:name)))
        @test @inferred(f(data)) == ["A B", "C"]
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
        @test_throws MethodError (@pipe begin
            data
            map((; _.name, n=length(↑)))
        end)

        @test (@pipe begin
            data
            map((; _.name, n=length(↑)), ↑)
        end) == [(name = "A B", n = 2), (name = "C", n = 2)]

        @test (@pipe begin
            data
            @asis map(x -> length(x.values) > 3, ↑)
        end) == [true, false]

        let
            g(x) = length(x.values)
            @test (@pipe begin
                data
                @asis map(g, ↑)
            end) == [4, 2]
        end

        let
            h(x) = length(x)
            @test (@pipe begin
                @asis h(data)
            end) == 2
        end

        @test_throws ErrorException @eval(@pipe begin
            data
            @asis map(length(_.values) > 3, ↑)
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

    @testset "errors" begin
        @test_throws UndefVarError @pipe begin
            data
            map((_, _1))
        end

        @test_throws UndefVarError @pipe begin
            data
            map((_, __2))
        end

        @test_throws String try @eval(@pipe begin
            data
            map(__)
        end) catch e; throw(e.error) end

        @test_throws String try @eval(@pipe begin
            data
            map(___)
        end) catch e; throw(e.error) end

        @test_throws String try @eval(@test @pipe begin
            data
            mapmany(_.values, ___)
        end) catch e; throw(e.error) end
    end

    @test data == data_original
end
