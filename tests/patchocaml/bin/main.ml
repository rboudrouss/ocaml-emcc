(* ohex and greet are built for the target with the patches of their
   recipes (emcc-recipes/): Ohex.wasm and greet.web exist only there *)
let () =
  print_endline (Ohex.encode "wasm");
  Printf.printf "patched: %b\n" Ohex.wasm;
  print_endline (Greet_web.hello ())
