mapmany(f_out, f_in, A) = [
	f_in(a, b)
	for a in A
    for b in f_out(a)]

mutate(f, A) = map(a -> merge(a, f(a)), A)
mutate(A; kwargs...) = mutate(a -> map(fx -> fx(a), values(kwargs)), A)

nt_first(nt::NamedTuple{Ss}) where{Ss} = NamedTuple{(Ss[1],)}((getfield(nt, Ss[1]),))
nt_tail(nt::NamedTuple) = Base.tail(nt)
merge_iterative(init; funcs...) = _merge_iterative(init, (;funcs...))
_merge_iterative(init, funcs) = _merge_iterative(merge(init, map(f -> f(init), nt_first(funcs))), nt_tail(funcs))
_merge_iterative(init, funcs::NamedTuple{()}) = init
mutate_(A; kwargs...) = map(a -> merge_iterative(a; kwargs...), A)
