(* mlcuddidl: CUDD (vendored C) through camlidl stubs.  BDD nodes are
   custom blocks that CUDD reference-counts and the GC finalizes, and Add's
   user operations are OCaml closures that CUDD calls back during its
   recursive apply, with Gc.compact moving the heap underneath (Add_part:
   OCaml < 5, mlcuddidl's opam patch for OCaml 5 removes Add). *)
open Cudd

(* N queens: one variable per square *)
let queens man n =
  let v i j = Bdd.ithvar man (i * n + j) in
  let all = ref (Bdd.dtrue man) in
  let ( &&& ) a b = Bdd.dand a b in
  for i = 0 to n - 1 do
    (* a queen on each row *)
    let row = ref (Bdd.dfalse man) in
    for j = 0 to n - 1 do row := Bdd.dor !row (v i j) done;
    all := !all &&& !row;
    for j = 0 to n - 1 do
      (* (i, j) excludes its row, column and diagonals *)
      let excl = ref (Bdd.dtrue man) in
      for k = 0 to n - 1 do
        for l = 0 to n - 1 do
          if (k, l) <> (i, j) && (k = i || l = j || k - l = i - j || k + l = i + j) then
            excl := !excl &&& Bdd.dnot (v k l)
        done
      done;
      all := !all &&& Bdd.dor (Bdd.dnot (v i j)) !excl
    done
  done;
  !all

let () =
  let man = Man.make_v () in
  List.iter (fun n ->
      let q = queens man n in
      Printf.printf "%d queens: %.0f solutions, %d nodes\n" n (Bdd.nbminterms (n * n) q) (Bdd.size q))
    [ 4; 6; 8 ];
  (* quantification, support, equivalences *)
  let x = Bdd.ithvar man 0 and y = Bdd.ithvar man 1 and z = Bdd.ithvar man 2 in
  let f = Bdd.dor (Bdd.dand x y) (Bdd.dand (Bdd.dnot x) z) in
  Printf.printf "ite: %b, support [%s]\n" (Bdd.is_equal f (Bdd.ite x y z))
    (String.concat ";" (List.map string_of_int (Bdd.list_of_support (Bdd.support f))));
  Printf.printf "exists x: %b, forall x: %b\n"
    (Bdd.is_equal (Bdd.exist (Bdd.support x) f) (Bdd.dor y z))
    (Bdd.is_equal (Bdd.forall (Bdd.support x) f) (Bdd.dand y z));
  Format.printf "f = %a@." (Bdd.print_minterm (fun fmt i -> Format.pp_print_string fmt [| "x"; "y"; "z" |].(i))) f;
  Gc.full_major ();
  Add_part.run ();
  Gc.compact ();
  print_endline "done"
