(* depgraph is an installed opam package (pkg/) with C stubs on mpfr, whose
   flags its dune rules get from pkg-config, and an OCaml dependency on
   zarith: ocaml-emcc builds the whole graph (gmp, mpfr, zarith's stubs and
   depgraph's) from this program alone. *)
let () =
  List.iter
    (fun n ->
      let z = Z.pow (Z.of_int n) 7 in
      Printf.printf "sqrt(%s) = %s\n" (Z.to_string z) (Depgraph.sqrt z 40))
    [ 2; 3; 1000 ];
  print_endline (Depgraph.versions ())
