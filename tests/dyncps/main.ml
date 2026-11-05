(* A program compiled with --cps-stack loading plugins, on node's main
   thread (the stack of a browser) *)
let load f =
  match Emcc_dynlink.loadfile f with
  | () -> Printf.printf "loaded %s\n%!" f
  | exception Failure s -> Printf.printf "%s: Failure %s\n%!" f s

let () = List.iter load [ "out/pdeep.wasm"; "out/pplain.wasm"; "out/nodt.wasm" ]
