using DataPipes
using Test
using Accessors


module MyModule
myfunc(x) = 2x
end


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
    @test (@pipe let
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

    @test (@pipe begin
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

    @test (@pipe map(_.name, data)) == ["A B", "C"]

    @test @p(1:4 |> Base.identity) == 1:4
    @test @p("abc" |> map(_ + 1)) == "bcd"
    @test @p(2+1im |> __.re) == 2

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

    @test @pipe(map(_ + _2, 1:3, 10:12)) == [11, 13, 15]
    @test @pipe(map(_ + _3, 1:3, [nothing, nothing, nothing], 10:12)) == [11, 13, 15]

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
    @test (@p begin
        "abc"
        uppercase()
    end) == "ABC"
    @test (@p begin
        "abc"
        uppercase(__)
    end) == "ABC"

    @test (@p begin
        1:3
        map(_, (__) .* 10)
    end) == [10, 20, 30]
    @test (@p begin
        1:3
        map((__) .* 10) do _
            _
        end
    end) == [10, 20, 30]
    @test (@p begin
        1:3
        map((__) .* 10) do x
            x
        end
    end) == [10, 20, 30]

    # start pipe anew: use @asis
    # works with literal values...
    @test (@p begin
        1:5
        map(_ * 2)
        res_a = filter(_ > 3)
        @asis 10:50
        map(_ ^ 2)
        map((_1, _2), res_a, __)
    end) ==  [(4, 100), (6, 121), (8, 144), (10, 169)]
    # and with variables
    x = 1:5
    y = 10:50
    @test (@p begin
        x
        map(_ * 2)
        res_a = filter(_ > 3)
        @asis y
        map(_ ^ 2)
        map((_1, _2), res_a, __)
    end) ==  [(4, 100), (6, 121), (8, 144), (10, 169)]

    f = function(X)
        @p begin
            X
            filter(_ > 2)
            @aside isempty(__) && return nothing
        end
        123
    end
    @test f(1:5) == 123
    @test f(1:2) === nothing
    f = function(X)
        @p begin
            X
            @aside count(x -> x > 2, __) == 0 && return nothing
            filter(_ > 2)
        end
        123
    end
    @test f(1:5) == 123
    @test f(1:2) === nothing
end

@testset "composable pipe" begin
    @test @pipe(begin
        data
        map(@pipe(_ꜛ))
    end) == [(name = "A B", values = [1, 2, 3, 4]), (name = "C", values = [5, 6])]
    @test @pipe(begin
        data
        map(@pipe(_ꜛ.name))
    end) == ["A B", "C"]

    @test @pipe(begin
        data
        map(@pipe(_ꜛ.name, collect, map(_^2), join(__, "")))
    end) == ["AA  BB", "CC"]

    @test @pipe(begin
        data
        map(@pipe(_ꜛ.name, collect, map(lowercase(_)^2), join(__, "")))
    end) == ["aa  bb", "cc"]

    @test @pipe(begin
        data
        map(@pipe(_ꜛ.name, collect, map(@pipe(_ꜛ, string, lowercase, (__)^2)), join(__, "")))
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
        map((;_.name, values=@pipe(_ꜛ.values |> map(_^2))))
    end) == [
        (name="A B", values=[1, 4, 9, 16]),
        (name="C", values=[25, 36]),
    ]

    @test (@pipe begin
        data
        map((;_.name, values=@p(_ꜛ.values |> map(_^2))))
    end) == [
        (name="A B", values=[1, 4, 9, 16]),
        (name="C", values=[25, 36]),
    ]

    @test (@pipe begin
        data
        map((;_.name, values=@pipe(_ꜛ.values |> map(_^2) |> map((n=_ꜛ.name, v=_)))))
    end) == [
        (name="A B", values=[(n="A B", v=1), (n="A B", v=4), (n="A B", v=9), (n="A B", v=16)]),
        (name="C", values=[(n="C", v=25), (n="C", v=36)]),
    ]

    @test (@p begin
        data
        map((;_.name, values=_.values |> @f(map(_^2) |> map((n=_ꜛ.name, v=_)))))
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
    @test (@p begin
        data
        map() do _
            @p begin
                _ꜛ.values
                map() do _
                    @p _ꜛ
                end
            end
        end
    end) == [[1, 2, 3, 4], [5, 6]]
end

@testset "implicit inner pipe" begin
    @test (@p begin
        data
        map() do __
            __.values
            map(_ ^ 2)
        end
    end) == [[1, 4, 9, 16], [25, 36]]
    @test (@p map(__ -> __.values |> map(_ ^ 2), data)) == [[1, 4, 9, 16], [25, 36]]
    @test (@p data |> map(__ -> __.values |> map(_ ^ 2))) == [[1, 4, 9, 16], [25, 36]]
    @test (@p data |> map(__ -> __.values |> map((v2=_ ^ 2, cnt=_ꜛ.values |> length)))) == [[(v2 = 1, cnt = 4), (v2 = 4, cnt = 4), (v2 = 9, cnt = 4), (v2 = 16, cnt = 4)], [(v2 = 25, cnt = 2), (v2 = 36, cnt = 2)]]

    @test (@p begin
        data
        map() do (name, __)
            map(_ ^ 2)
            sum()
            (;name, total=__)
        end
    end) == [(name="A B", total=30), (name="C", total=61)]

    @test @p(1:3 |> sort(by=__ -> map(-_))) == [3, 2, 1]
    @test @p(1:3 |> sort(; by=__ -> map(-_))) == [3, 2, 1]
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
        sort(; by=length(_.values))
    end) == [
        (name="C", values=[5, 6]),
        (name="A B", values=[1, 2, 3, 4]),
    ]

    @test (@pipe begin
        data
        sort(__; by=length(_.values))
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

    @test (@pipe begin
        data
        sort(; by=length(_.values), rev=true)
    end) == [
        (name="A B", values=[1, 2, 3, 4]),
        (name="C", values=[5, 6]),
    ]

    rev = true
    @test (@pipe begin
        data
        sort(; by=length(_.values), rev)
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

    @test (@p sum(1:5; init=100) do _
        -_
    end) == 85

    @test (@p 1:5 |> sum(init=100) do _
        -_
    end) == 85

    @test (@p 1:5 |> Iterators.product(__, [1, 2]) |> collect) == [(1, 1) (1, 2); (2, 1) (2, 2); (3, 1) (3, 2); (4, 1) (4, 2); (5, 1) (5, 2)]
end

@testset "Accessors.jl" begin
    @test (@p data |> map(@optic(_.name))) == ["A B", "C"]
    @test (@p data |> map(@set(_.name = "newname")) |> map(_.name)) == ["newname", "newname"]
    @test_broken (@p data |> map(@set(_ |> _.name = "newname")) |> map(_.name)) == ["newname", "newname"]
    @test (@p data |> map(x -> @set(x |> _.name = "newname")) |> map(_.name)) == ["newname", "newname"]
    @test (@p data |> map(x -> @set(x |> _.name = length(__)), __) |> map(_.name)) == [2, 2]

    @test (@p data |> map(set(_, @optic(_.name), "newname")) |> map(_.name)) == ["newname", "newname"]
    @test (@p data |> map(set(_, @o(_.name), "newname")) |> map(_.name)) == ["newname", "newname"]
    @test (@p data |> map(x -> set(x, @o(_.name), "newname")) |> map(_.name)) == ["newname", "newname"]

    @test (@p data |> @modify(x -> x + 1, (__ |> Elements()).values |> Elements())) == [(name = "A B", values = [2, 3, 4, 5]), (name = "C", values = [6, 7])]
    @test (@p data |> @modify((__ |> Elements()).values |> Elements()) do x x + 1 end) == [(name = "A B", values = [2, 3, 4, 5]), (name = "C", values = [6, 7])]
end

@testset "explicit arg" begin
    @test (@pipe begin
        data
        first()
        first((__).values)
    end) == 1

    @test (@pipe begin
        data
        first(first(__).values)
    end) == 1

    @test (@pipe begin
        data
        __
    end) == data

    @test (@pipe begin
        data
        (__)[1]
    end) == (name = "A B", values = [1, 2, 3, 4])

    @test (@pipe begin
        data
        (__)[1].values[1]
    end) == 1

    @test (@p (x -> x + 1) |> __(1)) == 2
    @test (@p (x -> !x) |> (!__)(true)) == true
    
    @test (@pipe begin
        (1, 2, 3)
        NamedTuple{(:a, :b, :c)}()
    end) == (a=1, b=2, c=3)
    @test (@pipe begin
        (1, 2, 3)
        NamedTuple{(:a, :b, :c)}(__)
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
        @_ map(_ + _2, a, b)
    end) == [7, 9, 11, 13, 15]

    @test (@pipe begin
        a = 1:5
        @_ b = 6:10
        @_ map(_ + _2, a, b)
    end) == [7, 9, 11, 13, 15]

    @test_throws MethodError (@pipe begin
        data
        map((; _.name, n=length(__)))
    end)

    @test (@pipe begin
        data
        map((; _.name, n=length(__)), __)
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
        sum(__) / sum(orig)
    end) == 2.9
    @test_throws UndefVarError orig
    @test_throws UndefVarError filt

    # XXX: not needed in reality; tests fail without this for some reason
    orig2 = orig3 = filt2 = val = ix = nothing

    @test (@pipe begin
        @export orig2 = [1, 2, 3, 4]
        map(_^2)
        filter(_ >= 4)
        sum(__) / sum(orig2)
    end) == 2.9
    @test orig2 == [1, 2, 3, 4]

    @test (@pipe begin
        @export orig3 = [1, 2, 3, 4]
        map(_^2)
        @export filt2 = filter(_ >= 4)
        sum(__) / sum(orig3)
    end) == 2.9
    @test orig3 == [1, 2, 3, 4]
    @test filt2 == [4, 9, 16]

    @test (@pipe let
        [1, 2, 3, 4]
        map(_^2)
        val, ix = findmax()
        @asis val^2
    end) == 256
    @test val === nothing && ix === nothing

    @test (@pipe let
        [1, 2, 3, 4]
        map(_^2)
        @export val, ix = findmax()
        @asis val^2
    end) == 256
    @test val == 16 && ix == 4

    # test that defining variables beforehand is not required; for some reason, only works in a function
    f = () -> begin
        r = @pipe let
            [1, 2, 3, 4]
            map(_^2)
            @export val1, ix1 = findmax()
            @asis val1^2
        end
        return r, val1, ix1
    end
    @test f() == (256, 16, 4)

    @test (@pipe begin
        [1, 2, 3, 4]
        map(_^2)
        valb, ixb = findmax()
        @asis val^2
    end) == 256
    @test val == 16 && ix == 4
end

@testset "aside" begin
    tmp = []
    @test (@p begin
        1:5
        map(_^2)
        @aside push!(tmp, last(__))
        map(_ + 1)
    end) == [2, 5, 10, 17, 26]
    @test tmp == [25]

    @test (@p let
        1:5
        map(_^2)
        @aside sum()
    end) == [1, 4, 9, 16, 25]
    @test (@p begin
        1:5
        map(_^2)
        @aside sum()
    end) == [1, 4, 9, 16, 25]

    # tmp = []
    # @test (@p begin
    #     1:5
    #     map(_^2)
    #     @→ push!(tmp, last(__))
    #     map(_ + 1)
    # end) == [2, 5, 10, 17, 26]
    # @test tmp == [25]

    x, y = nothing, nothing
    @test (@p begin
        1:5
        map(_^2)
        @aside @export x = last(__)
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

    tmp = []
    @test (@p begin
        1:5
        map() do x
            @p begin
                x
                [__, __^2]
                @aside push!(tmp, __)
                sum()
            end
        end
    end) == [2, 6, 12, 20, 30]
    @test tmp == [[1, 1], [2, 4], [3, 9], [4, 16], [5, 25]]

    tmp = []
    @test (@p begin
        1:5
        map() do __
            [__, __^2]
            @aside push!(tmp, __)
            sum()
        end
    end) == [2, 6, 12, 20, 30]
    @test tmp == [[1, 1], [2, 4], [3, 9], [4, 16], [5, 25]]

    @test (@p 1:5 |> @aside(x=first(__)) |> map(_ - x)) == [0, 1, 2, 3, 4]

    @test (@p begin
        1:5
        @aside x = __ |> @f map(_^2) |> sum
        map(_ * x)
    end) == [55, 110, 165, 220, 275]
end

@testset "underscore as keyword name" begin
    @test (@p 1:5 |> map((;_=_^2))) == [(_=1,), (_=4,), (_=9,), (_=16,), (_=25,)]
    @test (@p 1:5 |> map((;__=_^2))) == [(__=1,), (__=4,), (__=9,), (__=16,), (__=25,)]
    @test (@p 1:5 |> map((;__=_^2), __)) == [(__=1,), (__=4,), (__=9,), (__=16,), (__=25,)]
    @test_throws MethodError (@p 1:5 |> map((;_=__, __=_)))
    @test (@p 1:5 |> map((;_=__, __=_), __)) == [(_=1:5, __=1), (_=1:5, __=2), (_=1:5, __=3), (_=1:5, __=4), (_=1:5, __=5)]
    @test_throws MethodError (@p 1:5 |> map((;_=__), __))
    @test (@p 1:5 |> map((;_2=_^2))) == [(_2=1,), (_2=4,), (_2=9,), (_2=16,), (_2=25,)]
    @test (@p 1:5 |> map(_ -> (;_=__), __)) == [(_=1:5,), (_=1:5,), (_=1:5,), (_=1:5,), (_=1:5,)]
    @test (@p 1:5 |> map(x -> (;_=__), __)) == [(_=1:5,), (_=1:5,), (_=1:5,), (_=1:5,), (_=1:5,)]
    @test (@p 1:5 |> map(x -> (_=__, a=1), __)) == [(_=1:5, a=1), (_=1:5, a=1), (_=1:5, a=1), (_=1:5, a=1), (_=1:5, a=1)]
    @test (@p 1:5 |> identity((;_=__))) == (_=1:5,)
    @test (@p 1:5 |> identity((;_=__, a=123))) == (_=1:5, a=123)
    @test (@p 1:5 |> identity((_=__, a=123))) == (_=1:5, a=123)
end

@testset "debug mode" begin
    @test (@pDEBUG begin
        1:5
        map(_ * 2)
        res_a = filter(_ > 3)
    end) == [4, 6, 8, 10]
    @test (@pDEBUG begin
        1:5
        map(_ * 2)
        @aside res_a = filter(_ > 3)
        map((_1, _2), __, res_a)
    end) == [(2, 4), (4, 6), (6, 8), (8, 10)]
    # @test doesn't populate variables outside, so we'll run the same pipes again

    @testset "simple" begin
        @pDEBUG begin
            1:5
            map(_ * 2)
            res_a = filter(_ > 3)
        end
        @test _pipe == [1:5, 2:2:10, [4, 6, 8, 10]]
        @test res_a == [4, 6, 8, 10]
    end

    @testset "with @aside" begin
        @pDEBUG begin
            1:5
            map(_ * 2)
            @aside res_a = filter(_ > 3)
            map((_1, _2), __, res_a)
        end
        @test _pipe == [1:5, 2:2:10, [4, 6, 8, 10], [(2, 4), (4, 6), (6, 8), (8, 10)]]
        @test res_a == [4, 6, 8, 10]
    end

    @testset "errors" begin
        @test_throws ArgumentError @pDEBUG begin
            1:5
            map(_ * 3)
            @aside res_a = filter(_ > 3)
            map((_1, _2), __, res_a)
            only()
        end
        @test _pipe == [1:5, 3:3:15, [6, 9, 12, 15], [(3, 6), (6, 9), (9, 12), (12, 15)]]
        @test res_a == [6, 9, 12, 15]
    end

    @testset "outside of func" begin
        f() = @pDEBUG begin
            10:10:50
            map(_ * 2)
            @aside res_a = filter(_ > 30)
            map((_1, _2), __, res_a)
        end
        f()
        @test _pipe == [10:10:50, 20:20:100, [40, 60, 80, 100], [(20, 40), (40, 60), (60, 80), (80, 100)]]
        @test res_a == [40, 60, 80, 100]
    end
end

@testset "errors" begin
    @test_throws UndefVarError @pipe begin
        data
        map((_, _ꜛ))
    end
end

@test data == data_original


import CompatHelperLocal
CompatHelperLocal.@check()
