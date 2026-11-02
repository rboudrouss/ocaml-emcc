(* In a web page (tests/jsdom/check.mjs): elements, an event handler
   running after the main program, and a function exported to the page *)
open Js_of_ocaml

let () =
  let doc = Dom_html.document in
  let out = Dom_html.createDiv doc in
  out##.id := Js.string "out";
  out##.textContent := Js.some (Js.string "ready");
  Dom.appendChild doc##.body out;
  let button = Dom_html.createButton doc in
  button##.id := Js.string "button";
  let clicks = ref 0 in
  button##.onclick :=
    Dom_html.handler (fun _ ->
        incr clicks;
        out##.textContent := Js.some (Js.string (Printf.sprintf "clicked %d" !clicks));
        Js._false);
  Dom.appendChild doc##.body button;
  Js.export "ocamlAdd" (Js.wrap_callback (fun a b -> a + b));
  Js.export "ocamlUpper" (Js.wrap_callback (fun s -> Js.string (String.uppercase_ascii (Js.to_string s))));
  print_endline "main done"
