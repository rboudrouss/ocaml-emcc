(* ocaml-expat: libexpat (conf-expat), callbacks from C *)
let () =
  let p = Expat.parser_create ~encoding:None in
  let depth = ref 0 in
  Expat.set_start_element_handler p (fun name attrs ->
    Printf.printf "%s<%s%s>\n" (String.make (2 * !depth) ' ') name
      (String.concat "" (List.map (fun (k, v) -> Printf.sprintf " %s=%S" k v) attrs));
    incr depth);
  Expat.set_end_element_handler p (fun name -> decr depth; Printf.printf "%s</%s>\n" (String.make (2 * !depth) ' ') name);
  Expat.set_character_data_handler p (fun s -> if String.trim s <> "" then Printf.printf "%stext %S\n" (String.make (2 * !depth) ' ') s);
  Expat.parse p "<root a='1'><item id=\"x\">hello &amp; bye</item><item id='y'/>";
  Expat.parse p "<n>caf\xc3\xa9</n></root>";
  Expat.final p;
  let p = Expat.parser_create ~encoding:None in
  (match Expat.parse p "<a><b></a>"; Expat.final p with
   | () -> print_endline "no error?"
   | exception Expat.Expat_error e -> Printf.printf "error: %s at line %d\n" (Expat.xml_error_to_string e) (Expat.get_current_line_number p));
  print_endline "done"
