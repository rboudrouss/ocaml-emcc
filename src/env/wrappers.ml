(* The toolchain of the sysroot: wrapper scripts with the paths baked in,
   plus the findlib toolchain that makes `dune build -x <target>` work, and
   the manifest.  Written by the `ocaml` recipe once the runtime is built. *)

(* Bumped whenever [write] changes: the CLI then regenerates the toolchain
   in existing sysroots (cheap: the runtime is not rebuilt), and the stubs
   built with it are built again (see [Stamp.toolchain]). *)
let version = "20"

(* [template] with each @KEY@ replaced *)
let subst vars template =
  List.fold_left
    (fun s (k, v) ->
      let key = "@" ^ k ^ "@" in
      let b = Buffer.create (String.length s) in
      let rec go i =
        match Str_util.find_from s i key with
        | Some j -> Buffer.add_string b (String.sub s i (j - i)); Buffer.add_string b v; go (j + String.length key)
        | None -> Buffer.add_string b (String.sub s i (String.length s - i))
      in
      go 0;
      Buffer.contents b)
    template vars

let script path contents =
  Compat.write_file path contents;
  Unix.chmod path 0o755

let symlink target link =
  (try Sys.remove link with Sys_error _ -> ());
  Unix.symlink target link

(* The C compiler dune is given: emcc with the target (and stub standard)
   flags built in.  Some packages replace dune's :standard C flags with
   their own (mlmpfr's (flags (:include c_flags.sexp))), which would drop
   -m64 and friends.
   -pthread is added when compiling, and dropped from links (lwt's
   configuration adds it): all the C code is compiled for threads, and the
   link of the program decides whether it has them (Toolchain.compile_flags).
   An executable the build runs is single-threaded.
   So is -fopenmp (nx): emscripten's OpenMP needs threads (shared memory,
   which the libraries built without it refuse); the code then runs
   serially (_OPENMP undefined).
   So are -march, -mtune and -mcpu (CPU tuning, nx's -march=native), which
   clang refuses for wasm, and -Ofast, deprecated (hacl's -Werror): -O3
   -ffast-math.  So are the host's headers (-I/usr/include..., from the
   host's pkg-config in a package configured on the host): their libc is not
   emscripten's, and a missing library reads better as a missing header.
   The headers and libraries of the sysroot come last (after the package's
   own): dune-configurator's C tests only get the C flags, not -I.  Its -I
   of the host's standard library becomes that of the runtime's headers
   (the target's caml/config.h: jst-config's ARCH_SIXTYFOUR).  Those of
   the host in CPATH and friends would come before them (the host's ffi.h
   for ctypes-foreign): the environment loses them.
   The C standard is left out for C++ (snappy's stubs: -x c++), which clang
   refuses with -std=gnu23; `register` is allowed there, as by g++ (gbddml:
   clang refuses it in C++17).  In C, functions declared without a
   prototype are no error under -Werror, as with gcc, which does not warn
   (cucumber's gherkin-c: clang's -Wdeprecated-non-prototype).
   An executable (-o X.exe, or without extension) is a program the build
   runs: ctypes' type generators print the layouts of the target's structs.
   It becomes a node script (the wasm inside, real files) dune can run, with
   the node of emscripten's configuration (memory64 for wasm64): the one in
   PATH can be older. *)
let emcc_wrapper =
  {|#!/bin/sh
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH
link=-L'@SYSROOT@/lib' std='@STUB_STD@' lang='@LANG_FLAGS@' prev= exe= inc=
for a; do
  shift
  case $a in -c|-E|-S|-M|-MM) link= ;; -xc++*|*.cc|*.cpp|*.cxx|*.C) std= lang=-Wno-register ;; esac
  case $prev$a in -xc++*) std= lang=-Wno-register ;; esac
  [ "$prev" = -o ] && case ${a##*/} in *.exe) exe=1 ;; *.*) exe= ;; *) exe=1 ;; esac
  prev=$a
  case $inc$a in
    -I|-isystem|-idirafter|-iquote) inc=$a; continue ;;
    -I/usr/include|-I/usr/include/*|-I/usr/local/include|-I/usr/local/include/*) ;;
    -I'@STDLIB@'|-I'@STDLIB@/') set -- "$@" -I'@SYSROOT@/lib/ocaml' ;;
    -isystem/usr/include|-isystem/usr/include/*|-isystem/usr/local/include|-isystem/usr/local/include/*) ;;
    -pthread|-fopenmp|-fopenmp=*|-march=*|-mtune=*|-mcpu=*) ;;
    -Ofast) set -- "$@" -O3 -ffast-math ;;
    *) set -- "$@" $inc "$a" ;;
  esac
  inc=
done
[ -n "$link" ] && [ -n "$exe" ] && set -- "$@" -sEXECUTABLE='@NODE@' -sSINGLE_FILE=1 -sEXIT_RUNTIME=1 -sNODERAWFS=1
[ -z "$link" ] && set -- @COMPILE_FLAGS@ "$@"
exec '@EMCC@' @TARGET_FLAGS@ $std $lang -idirafter '@SYSROOT@/include' $link "$@"
|}

let tool_wrapper =
  {|#!/bin/sh
OCAML_EMCC_HOST_BIN='@HOST_BIN@'
OCAML_EMCC_SYSROOT='@SYSROOT@'
OCAML_EMCC_CFLAGS='@CFLAGS@'
OCAML_EMCC_EMCC='@CC@'
EMAR='@EMAR@'
PATH='@EMSDK_BIN@':$PATH
export OCAML_EMCC_HOST_BIN OCAML_EMCC_SYSROOT OCAML_EMCC_CFLAGS OCAML_EMCC_EMCC EMAR PATH
exec sh '@SHARE@/tools/@TOOL@' "$@"
|}

(* the next @TOOL@ in PATH, after bin/path *)
let next_in_path =
  {|self='@SYSROOT@/bin/path' IFS=:
for d in $PATH; do
  [ "$d" = "$self" ] && continue
  [ -x "$d/@TOOL@" ] && exec "$d/@TOOL@" "$@"
done
echo "@TOOL@: not found" >&2; exit 127
|}

(* pkg-config (dune-configurator): the rules of the wasm context only see
   the wasm libraries of the sysroot, not the host's (lmdb would take the
   host's liblmdb instead of its own copy).  Those of the host context get
   the host's pkg-config.  The context is that of INSIDE_DUNE (its build
   directory), which dune sets for its rules: dune-configurator runs
   pkg-config from a temporary directory, and the working directory of
   other rules is in the context (also in dune's sandboxes,
   _build/.sandbox/<hash>/). *)
let pkg_config_wrapper =
  {|#!/bin/sh
case $INSIDE_DUNE/:$PWD/ in
  */default.@TARGET@/*)
    PKG_CONFIG_LIBDIR='@SYSROOT@/lib/pkgconfig' PKG_CONFIG_PATH=
    export PKG_CONFIG_LIBDIR PKG_CONFIG_PATH ;;
esac
|}
  ^ next_in_path

(* cmake, for the same reason: the find_package of a CMake build run by a
   rule of the wasm context look in the sysroot first (hdr_histogram's
   zlib), not only in the host's /usr. *)
let cmake_wrapper =
  {|#!/bin/sh
case $INSIDE_DUNE/:$PWD/ in
  */default.@TARGET@/*)
    CMAKE_PREFIX_PATH='@SYSROOT@'${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}; export CMAKE_PREFIX_PATH ;;
esac
|}
  ^ next_in_path

(* llvm-config, for the same reason: dune rules running it (a package
   configured on the host) get the wasm LLVM of the clang recipe in the wasm
   context.  clang too, but only for what the recipe's clang answers
   (-print-resource-dir, --version): it compiles nothing; emcc compiles
   (see [host_tool_wrapper]). *)
let llvm_wrapper =
  {|#!/bin/sh
case $INSIDE_DUNE/:$PWD/ in
  */default.@TARGET@/*)
    if [ -x '@SYSROOT@/bin/@TOOL@' ]; then
      case @TOOL@:$1 in llvm-config:*|clang:-print-resource-dir|clang:--version) exec '@SYSROOT@/bin/@TOOL@' "$@" ;; esac
    elif [ @TOOL@ = llvm-config ]; then
      echo "llvm-config: no wasm LLVM for @TARGET@ yet, build it with: ocaml-emcc install clang" >&2; exit 1
    fi
    [ @TOOL@ = clang ] && exec '@CC@' "$@" ;;
esac
|}
  ^ next_in_path

(* The C and C++ compilers, ar and ranlib, named as on the host: rules of
   the wasm context running a build of their own with them (qbf's picosat
   makefile: gcc, ar, ranlib; hdr_histogram's CMake: cc; bls12-381's
   build.sh: cc; uring's configure: clang) get emcc and its tools, with the
   flags of the sysroot's C compiler wrappers.  The host's elsewhere, and
   for the tools of the toolchain that need it (OCAML_EMCC_HOST_TOOLS:
   placeholder-dll's host shared objects). *)
let host_tool_wrapper =
  {|#!/bin/sh
[ -n "${OCAML_EMCC_HOST_TOOLS:-}" ] || case $INSIDE_DUNE/:$PWD/ in
  */default.@TARGET@/*) exec '@WRAPPED@' "$@" ;;
esac
|}
  ^ next_in_path

(* The node of emscripten's configuration *)
let emscripten_node () =
  let em_config = Filename.concat (Filename.dirname (Toolchain.emcc ())) "em-config" in
  match Env.capture em_config [ "NODE_JS" ] with
  | Some s ->
      let s = String.trim s in
      let s = if Str_util.starts_with ~prefix:"['" s then String.sub s 2 (String.length s - 2) else s in
      let s = match String.index_opt s '\'' with Some i -> String.sub s 0 i | None -> s in
      if s = "" then "1" else s
  | None -> "1"

(* The lines of the host's findlib.conf: destdir and path absolute (they may
   be relative to the file: destdir=".", path="./ocaml:." since ocamlfind
   1.9.9), an entry for each tool (dune reads tools of the host context from
   this file too, and a variable only defined for a predicate,
   ocamlmklib(wasm64), reads as "" there), none for ocamlopt: dune then
   looks for it next to the toolchain's ocamlc ($SYSROOT/bin), finds nothing
   and treats the wasm context as bytecode-only (there is no native wasm
   backend).  The host context finds it next to the host ocamlc as usual. *)
let findlib_conf ~host_conf ~destdir ~path =
  let key l =
    let l' = String.trim l in
    let i = ref 0 in
    while !i < String.length l' && l'.[!i] <> ' ' && l'.[!i] <> '=' do incr i done;
    let k = String.sub l' 0 !i in
    let rest = String.trim (String.sub l' !i (String.length l' - !i)) in
    if String.length l > 0 && l.[0] <> ' ' && Str_util.starts_with ~prefix:"=" rest then Some k else None
  in
  let lines =
    match host_conf with
    | Some s ->
        String.split_on_char '\n' s
        |> (fun l -> match List.rev l with "" :: r -> List.rev r | _ -> l)
        |> List.map (fun l ->
               match key l with
               | Some "destdir" -> Printf.sprintf "destdir=%S" destdir
               | Some "path" -> Printf.sprintf "path=%S" path
               | _ -> l)
    | None -> [ Printf.sprintf "destdir=%S" destdir; Printf.sprintf "path=%S" path ]
  in
  let has tool = List.exists (fun l -> key l = Some tool) lines in
  let lines = lines @ List.filter_map (fun t -> if has t then None else Some (Printf.sprintf "%s=%S" t t)) [ "ocamlc"; "ocamlmklib"; "ocamldep"; "ocamldoc" ] in
  String.concat "\n" (List.filter (fun l -> key l <> Some "ocamlopt") lines) ^ "\n"

let write () =
  let sysroot = Env.sysroot () and host_bin = Env.host_bin () and target = !Env.target in
  let file rel = Env.sysroot_file rel in
  let mkdir d = Source.sh "mkdir" [ "-p"; file d ] in
  List.iter mkdir [ "bin/path"; "findlib.conf.d"; "lib/findlib" ];
  let emcc = Toolchain.emcc () in
  let cc = file ("bin/emcc-" ^ target) in
  let words = String.concat " " in
  let stdlib = match Env.capture (Filename.concat host_bin "ocamlc") [ "-where" ] with Some s -> String.trim s | None -> "" in
  let vars =
    [ ("STDLIB", stdlib);
      ("SYSROOT", sysroot); ("TARGET", target); ("HOST_BIN", host_bin); ("EMCC", emcc); ("CC", cc);
      ("STUB_STD", words (Lazy.force Toolchain.stub_std)); ("TARGET_FLAGS", words (Toolchain.target_flags ()));
      ("COMPILE_FLAGS", words Toolchain.compile_flags);
      ("CFLAGS", words (Toolchain.base_cflags ())); ("EMAR", Toolchain.emar ());
      ("EMSDK_BIN", Filename.dirname emcc); ("SHARE", Env.share ()); ("NODE", emscripten_node ());
    ]
  in
  script cc (subst (("LANG_FLAGS", "-Wno-error=deprecated-non-prototype") :: vars) emcc_wrapper);
  (* (C++: em++, and no C standard) *)
  let cxx = file ("bin/em++-" ^ target) in
  script cxx
    (subst (("STUB_STD", "") :: ("LANG_FLAGS", "-Wno-register") :: ("EMCC", Filename.concat (Filename.dirname emcc) "em++") :: vars) emcc_wrapper);
  List.iter (fun t -> script (file ("bin/" ^ t)) (subst (("TOOL", t) :: vars) tool_wrapper)) [ "ocamlc"; "ocamlmklib" ];
  (* The other tools dune looks for next to the toolchain's ocamlc (rules
     using %{ocaml}, %{bin:ocamllex}...) are the host's.  Not ocamlopt: see
     [findlib_conf]. *)
  List.iter
    (fun t ->
      let h = Filename.concat host_bin t in
      if Sys.file_exists h then symlink h (file ("bin/" ^ t)))
    [ "ocaml"; "ocamllex"; "ocamlyacc"; "ocamlobjinfo"; "ocamlcp"; "ocamlmktop"; "ocamlprof" ];
  (* bin/path comes first in dune's PATH: rules running `ocamlmklib` *)
  symlink "../ocamlmklib" (file "bin/path/ocamlmklib");
  symlink "../ocamlmklib" (file "bin/path/ocamlmklib.opt");
  List.iter (fun t -> script (file ("bin/path/" ^ t)) (subst (("TOOL", t) :: vars) pkg_config_wrapper)) [ "pkg-config"; "pkgconf" ];
  List.iter (fun t -> script (file ("bin/path/" ^ t)) (subst (("TOOL", t) :: vars) llvm_wrapper)) [ "llvm-config"; "clang" ];
  script (file "bin/path/cmake") (subst (("TOOL", "cmake") :: vars) cmake_wrapper);
  List.iter
    (fun (t, w) -> script (file ("bin/path/" ^ t)) (subst (("TOOL", t) :: ("WRAPPED", w) :: vars) host_tool_wrapper))
    [ ("cc", cc); ("gcc", cc); ("c++", cxx); ("g++", cxx); ("clang++", cxx);
      ("ar", Toolchain.emar ()); ("ranlib", Filename.concat (Filename.dirname emcc) "emranlib") ];
  let prefix = Switch.prefix () in
  let ocamlfind args = match Env.capture (Filename.concat host_bin "ocamlfind") args with Some s -> Some (String.trim s) | None -> None in
  let host_conf = Option.value (ocamlfind [ "printconf"; "conf" ]) ~default:(Filename.concat prefix "lib/findlib.conf") in
  let findlib_path =
    match ocamlfind [ "printconf"; "path" ] with
    | Some p when p <> "" -> String.concat ":" (List.filter (( <> ) "") (String.split_on_char '\n' p))
    | _ -> Filename.concat prefix "lib"
  in
  let destdir = Option.value (ocamlfind [ "printconf"; "destdir" ]) ~default:(Filename.concat prefix "lib") in
  let host_conf = if Sys.file_exists host_conf then Some (Compat.read_file host_conf) else None in
  let destdir = if host_conf = None then Filename.concat prefix "lib" else destdir in
  Compat.write_file (file "findlib.conf") (findlib_conf ~host_conf ~destdir ~path:findlib_path);
  Compat.write_file
    (file ("findlib.conf.d/" ^ target ^ ".conf"))
    (subst
       (("PATH", findlib_path) :: vars)
       {|path(@TARGET@) = "@SYSROOT@/lib/findlib:@PATH@"
destdir(@TARGET@) = "@SYSROOT@/lib/findlib"
stdlib(@TARGET@) = "@STDLIB@"
ocamlc(@TARGET@) = "@SYSROOT@/bin/ocamlc"
ocamlmklib(@TARGET@) = "@SYSROOT@/bin/ocamlmklib"
ocamldep(@TARGET@) = "@HOST_BIN@/ocamldep"
ocamldoc(@TARGET@) = "@HOST_BIN@/ocamldoc"
|});
  let ocaml_version = match Env.capture (Filename.concat host_bin "ocamlc") [ "-vnum" ] with Some s -> String.trim s | None -> "" in
  Compat.write_file (file "manifest")
    (String.concat ""
       (List.map
          (fun (k, v) -> k ^ "=" ^ v ^ "\n")
          [
            ("toolchain", version); ("ocaml_version", ocaml_version); ("target", target);
            ("cflags", words (Toolchain.base_cflags ())); ("ldflags", words (Toolchain.target_flags ()));
            ("emcc_version", Lazy.force Toolchain.emcc_version); ("emcc", emcc); ("host_bin", host_bin);
          ]))
