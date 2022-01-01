mapmany(f_out, f_in, A) = [
	f_in(a, b)
	for a in A
    for b in f_out(a)]

mutate(f, A) = map(a -> merge(a, f(a)), A)
mutate(A; kwargs...) = mutate(a -> map(fx -> fx(a), values(kwargs)), A)
