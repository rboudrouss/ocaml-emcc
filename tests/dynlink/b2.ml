(* A plugin of two modules (b.cma), the second using the first and A *)
let () = App.register "b" (fun () -> print_endline (B1.greet (string_of_int (List.length A.squares))))
