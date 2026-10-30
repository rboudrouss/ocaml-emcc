open Ocaml_emcc

(* the checksum as driver.sh computed it before Recipe.sum: stamps written
   then must still match *)
let bash_sum path name =
  let script =
    {|IFS=:; for d in $1; do
        [ -f "$d/$2/recipe.sh" ] || continue
        cat "$d/$2/recipe.sh"
        find "$d/$2" -type f ! -path "$d/$2/recipe.sh" -print0 | LC_ALL=C sort -z | xargs -0r cat
      done | sha256sum | cut -c1-16|}
  in
  Option.get (Env.output_of "bash" [ "-c"; script; "sum"; String.concat ":" path; name ])

let run () =
  let root = Check.temp_dir () in
  let project = Filename.concat root "project" and builtin = Filename.concat root "builtin" in
  let path = [ project; builtin ] in
  Check.file builtin "gmp/recipe.sh" "SOURCE=system:gmp\nHEADER=gmp.h\n";
  Check.file builtin "zlib/recipe.sh" "SOURCE=system:zlib\nLINK=-lz\n";
  Check.file builtin "sdl2/recipe.sh" "SOURCE=none\nLINK=\"-lSDL2 -sUSE_SDL=2\"\n";
  Check.file builtin "libffi/recipe.sh" "SOURCE=system:libffi\nLINK='-lffi -sALLOW_TABLE_GROWTH'\n";
  Check.file builtin "clang/recipe.sh" "SOURCE=fetch\nLIB_PATTERNS='clang* LLVM*'\n";
  Check.file builtin "zarith/recipe.sh" "SOURCE=opam:zarith\nDEPENDS=gmp\n";
  Check.file builtin "zarith/patches/b.patch" "b\n";
  Check.file builtin "zarith/patches/a.patch" "a\n";
  Check.file builtin "zarith/patches/4.x/c.patch" "c\n";
  Check.file builtin "zarith/Z.patch" "Z\n";
  Check.file project "zarith/recipe.sh" "include_recipe zarith\n";
  Check.file project "cjson/recipe.sh" "SOURCE=git:https://github.com/DaveGamble/cJSON\n";
  let find n = Option.map (fun d -> Filename.basename (Filename.dirname d)) (Recipe.find ~path n) in
  Check.string_opt "find: project first" (Some "project") (find "zarith");
  Check.string_opt "find: builtin" (Some "builtin") (find "gmp");
  Check.string_opt "find: none" None (find "nope");
  Check.string "sum: as driver.sh" (bash_sum path "zarith") (Recipe.sum ~path "zarith");
  Check.string "sum: single" (bash_sum path "gmp") (Recipe.sum ~path "gmp");
  Check.string "sum: none" (bash_sum path "nope") (Recipe.sum ~path "nope");
  let lib x = Recipe.lib_recipe ~path x in
  Check.string_opt "lib_recipe: by name" (Some "gmp") (lib "gmp");
  Check.string_opt "lib_recipe: libX" (Some "libffi") (lib "ffi");
  Check.string_opt "lib_recipe: by LINK" (Some "zlib") (lib "z");
  Check.string_opt "lib_recipe: case" (Some "sdl2") (lib "SDL2");
  Check.string_opt "lib_recipe: pattern" (Some "clang") (lib "clang-cpp");
  Check.string_opt "lib_recipe: pattern 2" (Some "clang") (lib "LLVM-19");
  Check.string_opt "lib_recipe: not a C library" None (lib "zarith");
  Check.string_opt "lib_recipe: none" None (lib "cjson");
  Check.bool "glob" true (Recipe.glob "a*b?" "axxbc" && not (Recipe.glob "a*b" "ab c"))
