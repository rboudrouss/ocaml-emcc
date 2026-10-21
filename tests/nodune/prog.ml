external triple : int -> int = "ml_triple"
external hello : unit -> string = "ml_hello"
let () =
  print_endline (hello ());
  Printf.printf "triple 14 = %d\n" (triple 14);
  Printf.printf "unix time > 0: %b\n" (Unix.time () > 0.);
  Printf.printf "zarith 2^80 = %s\n" (Z.to_string (Z.shift_left Z.one 80))
