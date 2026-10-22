(* minisat: the C++ SAT solver vendored by the binding *)
let () =
  (* pigeonhole: n+1 pigeons in n holes is UNSAT; n in n is SAT *)
  let php pigeons holes =
    let s = Minisat.create () in
    let v p h = Minisat.Lit.make (p * holes + h + 1) in
    for p = 0 to pigeons - 1 do Minisat.add_clause_l s (List.init holes (v p)) done;
    for h = 0 to holes - 1 do
      for p = 0 to pigeons - 1 do
        for q = p + 1 to pigeons - 1 do Minisat.add_clause_l s [ Minisat.Lit.neg (v p h); Minisat.Lit.neg (v q h) ] done
      done
    done;
    match Minisat.solve s with
    | () ->
        let assign = List.init pigeons (fun p -> List.find (fun h -> Minisat.value s (v p h) = Minisat.V_true) (List.init holes Fun.id)) in
        Printf.printf "php %d %d: SAT, distinct holes %b\n" pigeons holes
          (List.length (List.sort_uniq compare assign) = pigeons)
    | exception Minisat.Unsat -> Printf.printf "php %d %d: UNSAT\n" pigeons holes
  in
  php 5 5; php 6 5; php 8 7;
  let s = Minisat.create () in
  let a = Minisat.Lit.make 1 and b = Minisat.Lit.make 2 in
  Minisat.add_clause_l s [ a; b ];
  Minisat.add_clause_l s [ Minisat.Lit.neg a ];
  Minisat.solve s;
  Printf.printf "b true: %b\n" (Minisat.value s b = Minisat.V_true);
  (match Minisat.solve ~assumptions:[| Minisat.Lit.neg b |] s with
   | () -> print_endline "sat?!" | exception Minisat.Unsat -> print_endline "unsat under assumption");
  print_endline "done"
