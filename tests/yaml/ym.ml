(* yaml (ctypes generated stubs, bundled libyaml: rebuilt by dune -x) *)
let doc = {|
name: ocaml-emcc
targets: [wasm32, wasm64]
web:
  opt: -O2
  mode: preload
numbers: [1, 2.5, -3, 0x1F, true, null]
text: |
  two
  lines
|}

let () =
  match Yaml.of_string doc with
  | Error (`Msg m) -> prerr_endline m; exit 1
  | Ok v ->
      print_string (Yaml.to_string_exn v);
      (match Yaml.Util.find_exn "targets" v with
      | Some (`A l) -> Printf.printf "%d targets\n" (List.length l)
      | _ -> print_endline "no targets");
      print_endline (Yaml.to_string_exn (`O [ ("k", `String "v"); ("list", `A [ `Float 1.; `Bool false ]) ]))
