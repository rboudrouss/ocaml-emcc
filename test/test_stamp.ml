open Ocaml_emcc

let run () =
  Check.strings "parse" [ "1.2"; "emcc-4.0.1"; "recipe=abc" ] (Stamp.parse "1.2 emcc-4.0.1 recipe=abc\n");
  Check.strings "parse without version" [ ""; "emcc-4.0.1"; "recipe=abc" ] (Stamp.parse " emcc-4.0.1 recipe=abc\n");
  Check.strings "parse empty" [ "" ] (Stamp.parse "");
  let f = [ "1.2"; "emcc-4"; "recipe=abc"; "opam=zarith" ] in
  Check.string_opt "field" (Some "zarith") (Stamp.field "opam" f);
  Check.string_opt "absent field" None (Stamp.field "deps" f);
  Check.string "version" "1.2" (Stamp.version f);
  Check.bool "current_toolchain: none recorded" false (Stamp.current_toolchain f);
  Check.bool "current_toolchain" true (Stamp.current_toolchain [ "1.2"; "emcc-4"; Stamp.toolchain ]);
  Check.bool "current_toolchain: older" false (Stamp.current_toolchain [ "1.2"; "emcc-4"; "toolchain=0" ]);
  Stamp.write "x" [ ""; "emcc-4" ];
  Check.option (fun l -> String.concat "," l) "write then read" (Some [ ""; "emcc-4" ]) (Stamp.read "x");
  Check.string "file" " emcc-4\n" (Compat.read_file (Stamp.file "x"));
  Check.strings "names" [ "x" ] (Stamp.names ());
  Stamp.remove "x";
  Check.bool "removed" true (Stamp.read "x" = None)
