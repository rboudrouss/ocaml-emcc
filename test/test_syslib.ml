open Ocaml_emcc

let objinfo =
  {|File /x/lib/zarith/zarith.cma
Force custom: no
Extra C object files: -lzarith -lgmp
Extra C options: -L/usr/lib -lfoo
Extra dynamically-loaded libraries: -lzarith
Unit name: Z
Extra C options: -lnotme
|}

let run () =
  Check.strings "objinfo_libs" [ "foo"; "gmp"; "zarith" ] (Syslib.objinfo_libs objinfo);
  Check.strings "conf_packages"
    [ "conf-gmp"; "conf-pkg-config"; "conf-zlib" ]
    (Syslib.conf_packages {|depends: [ "conf-zlib" "conf-gmp" {build} "conf-gmp" ] depexts: "conf-" "conf-pkg-config" "conf-Bad"|});
  let root = Check.temp_dir () in
  let sw = Switch.prefix () in
  Check.file sw ".opam-switch/packages/mlmpfr.4.2.1/opam" {|depends: [ "conf-mpfr" "conf-gmp" "conf-zlib" ]|};
  Check.file sw ".opam-switch/packages/conf-mpfr.3/opam" "";
  Check.file sw ".opam-switch/packages/conf-gmp.4/opam" "";
  Check.file root "r/gmp/recipe.sh" "SOURCE=system:gmp\n";
  Check.file root "r/mpfr/recipe.sh" "SOURCE=system:mpfr\n";
  Check.file root "r/zlib/recipe.sh" "SOURCE=system:zlib\n";
  (* conf-zlib is not installed *)
  Check.strings "recipes" [ "gmp"; "mpfr" ] (Syslib.recipes ~path:[ Filename.concat root "r" ] "mlmpfr");
  Check.strings "recipes: not installed" [] (Syslib.recipes ~path:[ Filename.concat root "r" ] "nope")
