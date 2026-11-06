(* A program with threads loading a plugin which starts threads, starting
   threads after the load which run the plugin's code, and loading a second
   plugin with load_url, whose callback runs after main *)
let run () =
  let ts = List.mapi (fun i f -> Thread.create (fun () -> App.add (f (i + 1))) ()) !App.hooks in
  List.iter Thread.join ts;
  Printf.printf "total %d\n%!" !App.total

let () =
  Emcc_dynlink.loadfile "out/p.wasm";
  print_endline "loaded out/p.wasm";
  run ();
  Emcc_dynlink.load_url "out/q.wasm" (function
    | Ok () -> print_endline "loaded out/q.wasm"; run ()
    | Error e -> print_endline (Printexc.to_string e));
  print_endline "main done"
