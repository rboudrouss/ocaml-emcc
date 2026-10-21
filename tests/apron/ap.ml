(* apron (box, octagons, polyhedra) and mlgmpidl, through camlidl stubs *)
open Apron

let env = Environment.make [| Var.of_string "x"; Var.of_string "y" |] [||]
let cons s = Parser.lincons1_of_string env s

let analyse name man =
  let a = Abstract1.of_lincons_array man env
      (let t = Lincons1.array_make env 3 in
       List.iteri (Lincons1.array_set t) [ cons "x>=0"; cons "y>=x+1"; cons "x+y<=10" ]; t) in
  let a = Abstract1.assign_linexpr man a (Var.of_string "x")
      (Parser.linexpr1_of_string env "x+2*y") None in
  Format.printf "%-6s %a@." name Abstract1.print a;
  let i = Abstract1.bound_variable man a (Var.of_string "x") in
  Format.printf "       x in %a@." Interval.print i

let () =
  analyse "box" (Box.manager_alloc ());
  analyse "oct" (Oct.manager_alloc ());
  analyse "polka" (Polka.manager_alloc_strict ());
  let q = Mpqf.of_frac 22 7 and z = Mpzf.of_string "123456789012345678901234567890" in
  Format.printf "mpq %s, %s@." (Mpqf.to_string (Mpqf.mul q q)) (Mpzf.to_string (Mpzf.mul z z));
  let r = Mpfr.init2 100 in
  ignore (Mpfr.const_pi r Mpfr.Near);
  Format.printf "pi %s@." (Mpfr.to_string r)
