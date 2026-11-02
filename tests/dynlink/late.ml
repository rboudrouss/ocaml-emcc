let () =
  Gc.compact ();
  App.register "late" (fun () -> print_endline (B1.greet "late"))
