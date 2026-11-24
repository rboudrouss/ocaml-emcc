(* apron's domains on PPL (polyhedra, strict polyhedra, grids), the
   polkaGrid product and fppol (GLPK) *)
open Apron

let env = Environment.make [| Var.of_string "x"; Var.of_string "y" |] [||]
let cons s = Parser.lincons1_of_string env s

let of_list man l =
  let t = Lincons1.array_make env (List.length l) in
  List.iteri (fun i s -> Lincons1.array_set t i (cons s)) l;
  Abstract1.of_lincons_array man env t

let analyse name man l =
  let a = of_list man l in
  let a = Abstract1.assign_linexpr man a (Var.of_string "x") (Parser.linexpr1_of_string env "x+2*y") None in
  Format.printf "%-9s %a@." name Abstract1.print a;
  let i = Abstract1.bound_variable man a (Var.of_string "x") in
  Format.printf "          x in %a@." Interval.print i

let () =
  let poly = [ "x>=0"; "y>=x+1"; "x+y<=10" ] in
  analyse "ppl" (Ppl.manager_alloc_loose ()) poly;
  analyse "pplstrict" (Ppl.manager_alloc_strict ()) [ "x>0"; "y>x"; "x+y<10" ];
  analyse "pplgrid" (Ppl.manager_alloc_grid ()) [ "y=2*x+1" ];
  analyse "polkagrid" (PolkaGrid.manager_alloc (Polka.manager_alloc_loose ()) (Ppl.manager_alloc_grid ()))
    (poly @ [ "y=2*x+1" ]);
  analyse "fpp" (Fpp.manager_alloc ()) poly;
  (* the join of two polyhedra, and an inclusion *)
  let man = Ppl.manager_alloc_loose () in
  let a = of_list man [ "x>=0"; "x<=1"; "y=0" ] and b = of_list man [ "x>=2"; "x<=3"; "y=1" ] in
  let j = Abstract1.join man a b in
  Format.printf "join      %a@.          %b %b@." Abstract1.print j (Abstract1.is_leq man a j)
    (Abstract1.is_leq man j a)
