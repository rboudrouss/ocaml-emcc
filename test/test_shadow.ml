open Ocaml_emcc

(* The recipes patching the OCaml code of a package, and the dependencies
   of one built from the sources of its recipe *)
let run () =
  let root = Check.temp_dir () in
  let f p c = Check.file root p c in
  let recipes = Filename.concat root "recipes" in
  Env.recipe_dirs := !Env.recipe_dirs @ [ recipes ];
  f "recipes/fromgit/recipe.sh" "SOURCE=git:https://example.org/fromgit.git\nREF=v1\nPATCH_OCAML=1\n";
  f "recipes/fromopam/recipe.sh" "SOURCE=opam:fromopam\nPATCH_OCAML=1\n";
  f "recipes/stubsonly/recipe.sh" "SOURCE=opam:stubsonly\nbuild() { :; }\n";
  f "recipes/fromdir/recipe.sh" "SOURCE=dir:src\n";
  Check.bool "from_recipe: git" true (Shadow.from_recipe "fromgit");
  Check.bool "from_recipe: opam" false (Shadow.from_recipe "fromopam");
  Check.bool "from_recipe: no PATCH_OCAML" false (Shadow.from_recipe "fromdir");
  Check.bool "patches_ocaml: git" true (Shadow.patches_ocaml "fromgit");
  Check.bool "patches_ocaml: opam" true (Shadow.patches_ocaml "fromopam");
  Check.bool "patches_ocaml: C stubs only" false (Shadow.patches_ocaml "stubsonly");
  Check.bool "version: from the recipe" true
    (match Shadow.version "fromgit" with Some v -> Str_util.starts_with ~prefix:"recipe-" v | None -> false);
  (* findlib packages of the switch, by the opam package installing them *)
  let switch = Option.get !Env.switch in
  let sf p c = Check.file switch p c in
  sf "lib/foo/META" "";
  sf "lib/baz/META" "";
  sf ".opam-switch/install/foo.changes" "added: [\n  \"lib/foo/META\" {\"F:0\"}\n]\n";
  sf ".opam-switch/install/bazpkg.changes" "added: [\n  \"lib/baz/META\" {\"F:0\"}\n]\n";
  f "work/dune" "(library\n (name x)\n (libraries foo.sub bar ; a comment\n  (select a.ml from (baz -> a.real.ml) (-> a.fake.ml))))\n";
  f "work/_build/default/dune" "(library (name y) (libraries other))\n";
  f "work/lib/dune" "(executable (name z) (libraries foo unix))\n";
  Check.strings "dune_deps" [ "bazpkg"; "foo" ] (Shadow.dune_deps "x" (Filename.concat root "work"));
  Check.strings "dune_deps: not itself" [ "bazpkg" ] (Shadow.dune_deps "foo" (Filename.concat root "work"))
