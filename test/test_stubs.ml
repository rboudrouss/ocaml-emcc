open Ocaml_emcc

let run () =
  let root = Check.temp_dir () in
  let f p c = Check.file root p c in
  (* archives, made by the host's ar *)
  f "a/x.o" "\000asm\001\000\000\000";
  f "a/a_very_long_object_name_for_gnu_ar.o" "\127ELF";
  f "a/h.o" "\127ELF";
  let ar out files =
    ignore (Env.run ~cwd:(Filename.concat root "a") ~out:Unix.stderr "ar" ("rcs" :: out :: files))
  in
  ar "libw.a" [ "x.o"; "a_very_long_object_name_for_gnu_ar.o" ];
  ar "libh.a" [ "h.o" ];
  let a n = Filename.concat root ("a/" ^ n) in
  Check.strings "Archive.names" [ "x.o"; "a_very_long_object_name_for_gnu_ar.o" ] (Archive.names (a "libw.a"));
  Check.bool "Archive.is_wasm" true (Archive.is_wasm (a "libw.a"));
  Check.bool "Archive.is_wasm: host" false (Archive.is_wasm (a "libh.a"));
  Check.bool "Archive.is_wasm: not an archive" true (Archive.is_wasm (a "x.o"));
  Check.option (fun l -> String.concat "," l) "Archive.members: not an archive" None
    (Option.map (List.map fst) (Archive.members (a "x.o")));
  (* text searches *)
  Check.bool "has_word" true (Files.has_word "let t = seal t" "seal");
  Check.bool "has_word: part of a word" false (Files.has_word "unsealed sealing" "seal");
  Check.bool "has_seq: ctypes stanza" true (Files.has_seq ~space:true "(lang dune 3.0)\n(using\tctypes 0.3)" "(using" [ "ctypes" ]);
  Check.bool "has_seq: needs a space" false (Files.has_seq ~space:true "(usingctypes)" "(using" [ "ctypes" ]);
  Check.bool "has_seq: caml include" true (Files.has_seq "#include  <caml/mlvalues.h>" "#include" [ "<caml/"; "\"caml/" ]);
  Check.bool "has_seq: other include" false (Files.has_seq "#include <stdio.h>\ncaml/" "#include" [ "<caml/"; "\"caml/" ]);
  (* layouts *)
  f "p1/src/types.ml" "module T (S : Cstubs_structs.TYPE) = struct let () = seal s end";
  f "p2/src/types.ml" "module T (S : Cstubs.Types.TYPE) = struct let x = S.constant end";
  f "p2/_build/default/src/t.ml" "let () = seal s";
  f "p3/src/dune" "(rule (action (run gen type_description)))";
  f "p3/src/s.ml" "let () = Ctypes.seal t";
  let layouts p = Shadow.computes_layouts (Filename.concat root p) in
  Check.bool "computes_layouts" true (layouts "p1");
  Check.bool "computes_layouts: constants only" false (layouts "p2");
  Check.bool "computes_layouts: dune rule" true (layouts "p3");
  (* the C files of a native archive *)
  f "s/_build/default/stubs.c" "";
  f "s/src/stubs.c" "";
  f "s/_build/default/gen.c" "";
  ar "../s/_build/default/libs.a" [ "x.o" ];
  Check.option (fun l -> String.concat "," l) "archive_sources: none for x.o" None
    (Stubs.archive_sources (Filename.concat root "s") (Filename.concat root "s/_build/default/libs.a"));
  f "s/x.c" "";
  Check.option (fun l -> String.concat "," l) "archive_sources" (Some [ Filename.concat root "s/x.c" ])
    (Stubs.archive_sources (Filename.concat root "s") (Filename.concat root "s/_build/default/libs.a"))
