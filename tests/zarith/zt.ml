let () =
  let rec fact n = if n <= 1 then Z.one else Z.mul (Z.of_int n) (fact (n - 1)) in
  let f100 = fact 100 in
  Printf.printf "100! = %s\n" (Z.to_string f100);
  Printf.printf "numbits(100!) = %d\n" (Z.numbits f100);
  Printf.printf "gcd(100!, 2^200-1) = %s\n" (Z.to_string (Z.gcd f100 (Z.pred (Z.shift_left Z.one 200))));
  let p = Z.of_string "170141183460469231731687303715884105727" in
  Printf.printf "2^127-1 probab_prime = %d\n" (Z.probab_prime p 25);
  Printf.printf "powm 3^(10^30) mod p = %s\n" (Z.to_string (Z.powm (Z.of_int 3) (Z.pow (Z.of_int 10) 30) p));
  Printf.printf "small fits int: %b, big fits int: %b\n" (Z.fits_int (Z.of_int max_int)) (Z.fits_int f100);
  Printf.printf "of_int64 max: %s\n" (Z.to_string (Z.of_int64 Int64.max_int));
  let q = Q.make (Z.of_int 355) (Z.of_int 113) in
  Printf.printf "Q 355/113 = %s ~ %.10f\n" (Q.to_string q) (Q.to_float q);
  (* before zarith 1.14, the hash depends on the word size: its low 30 bits do not *)
  Printf.printf "hash(100!) = %d, compare = %d\n" (Z.hash f100 land 0x3fff_ffff) (Z.compare f100 (Z.succ f100));
  let s = Marshal.to_string f100 [] in
  Printf.printf "marshal roundtrip: %b\n" (Z.equal f100 (Marshal.from_string s 0))
