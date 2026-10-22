(* snappy: C++ library (conf-snappy) through C stubs *)
let () =
  let s = String.concat "" (List.init 500 (fun i -> string_of_int (i mod 17))) in
  let c = Snappy.compress s in
  Printf.printf "snappy: %d -> %d, valid %b, size %d\n" (String.length s) (String.length c) (Snappy.is_valid c) (Snappy.get_uncompressed_size c);
  Printf.printf "roundtrip: %b\n" (Snappy.uncompress c = s);
  Printf.printf "invalid: %b\n" (Snappy.is_valid "\xff\xff\xff\xff\xff not snappy");
  (match Snappy.uncompress "\xff\xff\xff\xff\xff not snappy" with _ -> print_endline "no error?" | exception e -> Printf.printf "error: %s\n" (Printexc.to_string e));
  print_endline "done"
