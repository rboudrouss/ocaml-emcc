
let () =
  Printf.printf "cJSON %s\n" (Cjson.version ());
  let s, n, l, printed =
    Cjson.inspect {| { "name": "ocaml-emcc", "pi": 3.14159, "langs": ["ocaml", "c", "wasm"] } |} "name" "pi" "langs"
  in
  Printf.printf "name=%s pi=%g langs=%d\n%s\n" s n l printed;
  match Cjson.inspect "{ broken" "a" "b" "c" with
  | _ -> print_endline "parsed?!"
  | exception Failure m -> Printf.printf "Failure %s\n" m
