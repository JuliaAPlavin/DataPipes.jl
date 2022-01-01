mapmany(f_out, f_in, A) = [
	f_in(a, b)
	for a in A
    for b in f_out(a)]

mutate(f, A) = map(a -> merge(a, f(a)), A)
