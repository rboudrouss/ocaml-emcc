(* Plugins fetched by a web page (Emcc_dynlink.load_url), one after the
   other: those of tests/dynlink *)
let rec chain = function
  | [] ->
      App.run_all ();
      print_endline "end"
  | url :: rest ->
      Emcc_dynlink.load_url url (fun r ->
          (match r with
          | Ok () -> Printf.printf "loaded %s\n%!" url
          | Error (Failure s) -> Printf.printf "%s: Failure %s\n%!" url (List.hd (String.split_on_char '\n' s))
          | Error e -> Printf.printf "%s: %s\n%!" url (Printexc.to_string e));
          chain rest)

let () =
  chain [ "b.wasm"; "a.wasm"; "b.wasm"; "raises.wasm"; "late.wasm" ];
  print_endline "main done"
