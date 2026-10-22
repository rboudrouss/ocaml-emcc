(* binary data on stdout (NUL bytes, invalid UTF-8): under node, the
   program's descriptors are written as bytes *)
let () =
  print_string "text, then every byte value:\n";
  print_string (String.init 256 Char.chr);
  print_string "\nUTF-8: \xc3\xa9t\xc3\xa9 \xe2\x82\xac\n";
  Marshal.to_channel stdout ([ 1; 2; 3 ], "marshalled", 3.14) [];
  prerr_string "stderr too: \000\255\n";
  print_newline ()
