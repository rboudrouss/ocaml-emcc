(* Plugins (Emcc_dynlink), loaded from files and asynchronously *)
let load f =
  match Emcc_dynlink.loadfile f with
  | () -> Printf.printf "loaded %s\n%!" f
  | exception App.Plugin_error s -> Printf.printf "%s: Plugin_error %S\n%!" f s
  | exception Failure s -> Printf.printf "%s: Failure %s\n%!" f (List.hd (String.split_on_char '\n' s))
  | exception e -> Printf.printf "%s: %s\n%!" f (Printexc.to_string e)

let () =
  print_endline "main";
  load "out/b.wasm";
  load "out/a.wasm";
  load "out/b.wasm";
  load "out/a.wasm";
  load "out/raises.wasm";
  load "out/stale.wasm";
  load "out/nothing.wasm";
  App.run_all ();
  Emcc_dynlink.load_url "out/late.wasm" (function
    | Ok () -> print_endline "late.wasm loaded"; App.run_all ()
    | Error e -> print_endline (Printexc.to_string e));
  print_endline "main done"
