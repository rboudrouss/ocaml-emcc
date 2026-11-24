(* apron's PPLite domain (flint integers), each of its kinds *)
open Apron

let env = Environment.make [| Var.of_string "x"; Var.of_string "y" |] [||]

let of_list man l =
  let t = Lincons1.array_make env (List.length l) in
  List.iteri (fun i s -> Lincons1.array_set t i (Parser.lincons1_of_string env s)) l;
  Abstract1.of_lincons_array man env t

let () =
  let man = Pplite.manager_alloc_loose () in
  List.iter
    (fun kind ->
      Pplite.manager_set_kind man kind;
      let a = of_list man [ "x>=0"; "y>=x+1"; "x+y<=10" ] in
      let a = Abstract1.assign_linexpr man a (Var.of_string "x") (Parser.linexpr1_of_string env "x+2*y") None in
      let b = of_list man [ "x>=20"; "y=0" ] in
      let j = Abstract1.join man a b in
      Format.printf "%-7s %s %a@." kind (Pplite.manager_get_kind man) Abstract1.print a;
      (* (a powerset's join keeps both disjuncts) *)
      if Pplite.abstract0_is_disjunctive man (Abstract1.abstract0 j) then
        Format.printf "        join: %d disjuncts@." (Pplite.abstract0_num_disjuncts man (Abstract1.abstract0 j))
      else Format.printf "        join %a@." Abstract1.print j)
    [ "Poly"; "F_Poly"; "U_Poly"; "UF_Poly"; "P_Set" ];
  let s = Pplite.manager_alloc_strict () in
  Format.printf "strict  %a@." Abstract1.print (of_list s [ "x>0"; "y>x"; "x+y<10" ])
