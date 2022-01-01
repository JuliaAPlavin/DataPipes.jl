using DataPipes
using Test

import CompatHelperLocal
CompatHelperLocal.@check()


@testset begin
    data = [
        (name="A B", values=[1, 2, 3, 4]),
        (name="C", values=[5, 6]),
    ]
    data_original = copy(data)

    @testset "simple" begin
        @test @pipe(data) == data

        @test @pipe(data, map(_.name)) == ["A B", "C"]

        @test (@pipe begin
            data
            map(_.name)
        end) == ["A B", "C"]

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
    end

    @testset "composable pipe" begin
        @test data |> @pipe(map(_.name)) == ["A B", "C"]
        @test data |> @pipe(map(_.name) |> map(_^2)) == ["A BA B", "CC"]
        @test @pipe(data) |> @pipe(map(_.name) |> map(_^2)) == ["A BA B", "CC"]
        @test @pipe(data, map(_.name)) |> @pipe(map(_^2)) == ["A BA B", "CC"]
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
    end

    @testset "keeping exp as-is" begin
        @test (@pipe begin
            data
            @asis map(x -> length(x.values) > 3, ↑)
        end) == [true, false]

        @test_throws ErrorException @eval(@pipe begin
            data
            @asis map(length(_.values) > 3, ↑)
        end)
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
