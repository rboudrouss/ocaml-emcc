open Ocaml_emcc

let listing =
  {|<a href="mpfr-3.1.6.tar.gz">mpfr-3.1.6.tar.gz</a> <a href="mpfr-4.2.1.tar.bz2">x</a>
<a href="mpfr-4.2.1.tar.xz">mpfr-4.2.1.tar.xz</a> mpfr-4.2.1.tar.xz.sig mpfr-4.10.0.tar.gz
mpfr-4.2.1.tar.gz mpfr-4.9.tar.gz mpfr-4.2.1.zip mpfr-.tar.gz libmpfr-1.0.tar.gz mpfr-5.0-rc1.tar.gz|}

(* the listing as driver.sh parsed it before Source.release_files *)
let bash_release_files prefix text =
  let script =
    {|grep -oE "$1-[0-9][0-9.]*[0-9]\.tar\.(xz|bz2|gz)" \
      | sed -E "s/^$1-([0-9.]*[0-9])\.tar\.(xz|bz2|gz)$/\1 \2 &/" \
      | sed -e 's/ xz / 1 /' -e 's/ bz2 / 2 /' -e 's/ gz / 3 /' \
      | sort -k1,1V -k2,2n -u | awk '$1 != last { print $1, $3; last = $1 }'|}
  in
  let f = Filename.temp_file "listing" "" in
  Compat.write_file f text;
  let out = Option.get (Env.output_of "bash" [ "-c"; "< " ^ Filename.quote f ^ " " ^ script; "rf"; prefix ]) in
  Sys.remove f;
  List.filter (( <> ) "") (String.split_on_char '\n' out)

let run () =
  Check.strings "release_files: as driver.sh" (bash_release_files "mpfr" listing) (Source.release_files "mpfr" listing);
  Check.strings "release_files"
    [ "1.0 mpfr-1.0.tar.gz"; "3.1.6 mpfr-3.1.6.tar.gz"; "4.2.1 mpfr-4.2.1.tar.xz"; "4.9 mpfr-4.9.tar.gz"; "4.10.0 mpfr-4.10.0.tar.gz" ]
    (Source.release_files "mpfr" listing);
  let sorted l = List.sort Source.compare_versions l in
  Check.strings "compare_versions" [ "1.2"; "1.9"; "1.10"; "1.10.1"; "2.0-1"; "10" ] (sorted [ "10"; "1.10.1"; "2.0-1"; "1.10"; "1.9"; "1.2" ]);
  let lines = [ "6.2.1 a"; "6.3.0 b"; "6.30 c"; "63 d"; "6 e"; "6-1 f" ] in
  Check.strings "version_match" [ "6.2.1 a"; "6.3.0 b"; "6.30 c"; "6 e"; "6-1 f" ] (Source.version_match "6" lines);
  Check.strings "version_match: minor" [ "6.3.0 b" ] (Source.version_match "6.3" lines);
  Check.strings "version_match: any" lines (Source.version_match "" lines);
  Check.string_opt "wanted: major" (Some "6") (Source.wanted ~compat:"" "6.3.0");
  Check.string_opt "wanted: minor" (Some "6.3") (Source.wanted ~compat:"minor" "6.3.0");
  Check.string_opt "wanted: exact" (Some "6.3.0") (Source.wanted ~compat:"exact" "6.3.0");
  Check.string_opt "wanted: latest" (Some "") (Source.wanted ~compat:"latest" "6.3.0");
  Check.string_opt "wanted: bad" None (Source.wanted ~compat:"newest" "6.3.0");
  let defs = "#define __GNU_MP_VERSION 6\n#define __GNU_MP_VERSION_MINOR 3\n#define ZLIB_VERSION \"1.3.1\"\n" in
  Check.string_opt "macro_values" (Some "6.3") (Source.macro_values defs [ "__GNU_MP_VERSION"; "__GNU_MP_VERSION_MINOR" ]);
  Check.string_opt "macro_values: string" (Some "1.3.1") (Source.macro_values defs [ "ZLIB_VERSION" ]);
  Check.string_opt "macro_values: missing" None (Source.macro_values defs [ "__GNU_MP_VERSION"; "NOPE" ])
