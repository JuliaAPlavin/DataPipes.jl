import SplitApplyCombine: mapmany


(name::Symbol)(x) = getfield(x, name)
(name::Val{S})(x) where {S} = getfield(x, S)

mapmany(f_out::Function, f_in::Function, A) = [
	f_in(a, b)
	for a in A
    for b in f_out(a)]

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


@generated function unnest1(nt::NamedTuple{KS, TS}) where {KS, TS}
    types = fieldtypes(TS)
    assigns = mapreduce(vcat, KS, types) do k, T
        if T <: NamedTuple
            ks = fieldnames(T)
            ks_new = [Symbol(k, :_, k_) for k_ in ks]
            map(ks, ks_new) do k_, k_n
                :( $k_n = nt.$k.$k_ )
            end
        else
            :( $k = nt.$k )
        end
    end
    quote
        ($(assigns...),)
    end
end

const unnest = unnest1
