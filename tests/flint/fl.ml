(* flint: FLINT through ctypes stubs, polynomials over Z, algebraic numbers
   (qqbar), calcium's exact reals *)
open Flint

let () =
  let p = FMPZ_poly.create [| Z.of_int (-1); Z.zero; Z.one |] (* x^2 - 1 *)
  and q = FMPZ_poly.create [| Z.of_int (-2); Z.zero; Z.one |] (* x^2 - 2 *) in
  let r = FMPZ_poly.mul p q in
  Printf.printf "(x^2-1)(x^2-2) = %s, length %d\n" (FMPZ_poly.to_string r) (FMPZ_poly.length r);
  let roots = QQBAR.from_roots r in
  Array.iter (fun x ->
      Format.printf "root: real %b, one %b, %a@." (QQBAR.is_real x) (QQBAR.is_one x) ACB.pp (QQBAR.enclosure x))
    roots;
  let ctx = CA.CTX.mk () in
  let s2 = CA.sqrt ~ctx (CA.of_int ~ctx 2) in
  let two = CA.mul ~ctx s2 s2 in
  Printf.printf "sqrt 2 = %s, its square %s (rational %s)\n" (CA.to_string ~ctx s2) (CA.to_string ~ctx two)
    (match CA.to_q ~ctx two with Some q -> Q.to_string q | None -> "no");
  let f = FMPZ.of_z (Z.pow (Z.of_int 3) 200) in
  Printf.printf "3^200 back: %b\n" (Z.equal (FMPZ.to_z f) (Z.pow (Z.of_int 3) 200))
