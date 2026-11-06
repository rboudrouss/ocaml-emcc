(* An interpreted program loading bytecode plugins with OCaml's Dynlink:
   .cmo and .cma files, with C stubs of their own (wasm dllX.so) *)
let load f =
  let name = Filename.basename f in
  match Dynlink.loadfile f with
  | () -> Printf.printf "loaded %s\n%!" name
  | exception Dynlink.Error (Dynlink.Cannot_open_dynamic_library e) ->
      (* (the message, without the printing of the exception, which
         differs between versions) *)
      let m = Printexc.to_string e and w = "no wasm dll" in
      let rec has i = i + String.length w <= String.length m && (String.sub m i (String.length w) = w || has (i + 1)) in
      Printf.printf "%s: cannot open its C%s\n%!" name (if has 0 then ", no wasm dllX.so" else ": " ^ m)
  | exception Dynlink.Error e -> Printf.printf "%s: %s\n%!" name (Dynlink.error_message e)

let () =
  Unix.putenv "OCAML_EMCC_STUBLIBS" "out/stublibs";
  Dynlink.allow_unsafe_modules true;
  List.iter load
    [ "a.cmo"; "b.cma"; "a.cmo"; "r.cmo"; "cst.cma"; "out/str.cma"; "u.cmo"; "nodll.cma" ];
  List.iter (fun f -> print_endline (f "x")) (List.rev !App.hooks)
