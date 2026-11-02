(* Plugins and effects: the program is compiled with --effects
   double-translation, its plugins follow (ocaml-emcc plugin --main) *)
let load f =
  match Emcc_dynlink.loadfile f with
  | () -> Printf.printf "loaded %s\n%!" f
  | exception Failure s -> Printf.printf "%s: Failure %s\n%!" f s

let () =
  load "out/p.wasm";
  load "out/nodt.wasm";
  App.with_answers (fun () -> List.iter (fun f -> f ()) (List.rev !App.hooks))
