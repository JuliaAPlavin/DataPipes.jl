import SplitApplyCombine: mapmany, mapview
using Accessors: insert

macro S_str(str)
    # :(Symbol($(esc(str)))) - simple version without interpolation
    str_interpolated = esc(Meta.parse("\"$(escape_string(str))\""))
    :(Symbol($str_interpolated))
end

(name::Symbol)(x) = getproperty(x, name)


# mapmany methods
function mapmany!(f::Function, out, A)
    empty!(out)
    for a in A
        append!(out, f(a))
    end
    out
end

# likely can replace with a SAC.mapmany call after https://github.com/JuliaData/SplitApplyCombine.jl/pull/54
mapmany(f_out::Function, f_in::Function, A) = reduce(vcat, map(a -> map(b -> f_in(a, b), f_out(a)), A))

function mapmany!(f_out::Function, f_in::Function, out, A)
    empty!(out)
    for a in A
        for b in f_out(a)
            push!(out, f_in(a, b))
        end
    end
    out
end


mutate_flat(f, A) = map(a -> merge(a, f(a)), A)
mutate_flat(A; kwargs...) = mutate_flat(a -> map(fx -> fx(a), values(kwargs)), A)

## vvv taken from NamedTupleTools.jl
struct Unvalued end
const unvalued = Unvalued()

merge_recursive(nt::NamedTuple) = nt

merge_recursive(::Unvalued, ::Unvalued) = unvalued
merge_recursive(x, ::Unvalued) = x
merge_recursive(m::Unvalued, x) = merge_recursive(x, m)
merge_recursive(x, y) = y

function merge_recursive(nt1::NamedTuple, nt2::NamedTuple)
    all_keys = union(keys(nt1), keys(nt2))
    gen = Base.Generator(all_keys) do key
        v1 = get(nt1, key, unvalued)
        v2 = get(nt2, key, unvalued)
        key => merge_recursive(v1, v2)
    end
    return (; gen...)
end
## ^^^

mutate_rec(f, A) = map(a -> merge_recursive(a, f(a)), A)

nt_first(nt::NamedTuple{Ss}) where{Ss} = NamedTuple{(Ss[1],)}((getfield(nt, Ss[1]),))
nt_tail(nt::NamedTuple) = Base.tail(nt)
merge_iterative(init; funcs...) = _merge_iterative(init, (;funcs...))
_merge_iterative(init, funcs) = _merge_iterative(merge(init, map(f -> f(init), nt_first(funcs))), nt_tail(funcs))
_merge_iterative(init, funcs::NamedTuple{()}) = init
mutate_seq(A; kwargs...) = map(a -> merge_iterative(a; kwargs...), A)

const mutate = mutate_flat


"""
Transform collection `A` by applying `f` to each element. Elements with `isnothing(f(x))` are dropped. Return `Some(nothing)` from `f` to keep `nothing` in the result.
"""
function filtermap(f, A...)
    map(something, filter!(!isnothing, map(f, A...)))
end

function filtermap(f, A::Tuple)
    map(something, filter(!isnothing, map(f, A)))
end

struct KeepSame end

@generated function _unnest(nt::NamedTuple{KS, TS}, ::Val{KEYS}=Val(nothing), ::Val{TARGET}=Val(KeepSame())) where {KS, TS, KEYS, TARGET}
    types = fieldtypes(TS)
    assigns = mapreduce(vcat, KS, types) do k, T
        if !isnothing(KEYS) && k ∈ KEYS && !(T <: NamedTuple)
            error("Cannot unnest field $k::$T")
        end

        if (isnothing(KEYS) || k ∈ KEYS) && T <: NamedTuple
            ks = fieldnames(T)
            tgt_k = TARGET isa KeepSame ? k : TARGET
            ks_new = map(ks) do k_
                isnothing(tgt_k) ? k_ : Symbol(tgt_k, :_, k_)
            end
            map(ks, ks_new) do k_, k_n
                :( $k_n = nt.$k.$k_ )
            end |> collect
        else
            :( $k = nt.$k )
        end
    end
    :( ($(assigns...),) )
end

@inline unnest(nt::NamedTuple) = _unnest(nt)
@inline unnest(nt::NamedTuple, k::Symbol) = _unnest(nt, Val((k,)))
@inline unnest(nt::NamedTuple, kv::Pair{Symbol, <:Union{Symbol, Nothing}}) = _unnest(nt, Val((first(kv),)), Val(last(kv)))
@inline unnest(nt::NamedTuple, ks::Tuple{Vararg{Symbol}}) = _unnest(nt, Val(ks))


vcat_data(ds...; kwargs...) = reduce(vcat_data, ds; kwargs...)
function Base.reduce(::typeof(vcat_data), ds; source=nothing)
    isnothing(source) ?
        reduce(vcat, ds) :
        mapmany(((k, d),) -> d, ((k, d), x) -> insert(x, source, k), zip(keys(ds), values(ds)))
end
