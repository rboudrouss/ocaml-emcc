(* The C stubs of opam packages built for the target: with the package's
   dune rules (dune build -x), from the C files of its native build, or
   blindly; and the patched dune that builds the (ctypes) stanza. *)

let log = Env.log
let sh ?cwd prog args = Env.run_exn ?cwd ~out:Unix.stderr prog args

(* --------------------------------------------------------- sysroot meta *)

let meta name = Env.sysroot_file (Filename.concat "meta" name)
let write_meta name s = Source.sh "mkdir" [ "-p"; Env.sysroot_file "meta" ]; Compat.write_file (meta name) (s ^ "\n")
let read_meta name = Str_util.words (String.trim (Files.contents (meta name)))

let install_lib f =
  Source.sh "mkdir" [ "-p"; Env.sysroot_file "lib" ];
  sh "cp" [ "-f"; f; Env.sysroot_file "lib/" ]

(* which recipe builds which library, so that `deps` knows how to obtain
   a missing lib<name>.a *)
let provides recipe libs = List.iter (fun l -> write_meta (l ^ ".provider") recipe) libs

(* extra flags needed when lib<lib>.a is linked (zarith needs -lgmp) *)
let link_flags lib flags = write_meta (lib ^ ".link") (String.concat " " flags)

(* lib<name>.a of [objs], in [dir] *)
let mklib dir name objs =
  let a = Filename.concat dir ("lib" ^ name ^ ".a") in
  (try Sys.remove a with Sys_error _ -> ());
  sh (Toolchain.emar ()) ("rcs" :: a :: objs);
  a

(* Compile one stub file against the runtime of the target: whether it
   compiled (to <file>.o) *)
let compile ?cwd ?(flags = []) c =
  Env.run ?cwd ~out:Unix.stderr (Toolchain.emcc ())
    (Toolchain.stub_cflags () @ flags @ [ "-c"; c; "-o"; Filename.remove_extension c ^ ".o" ])
  = 0

(* ----------------------------------------------------- system libraries *)

(* Build the system recipes [pkg] uses (Syslib.recipes); the link flags
   they require *)
let system_deps pkg =
  Compat.concat_map
    (fun r ->
      log "%s uses the system library %s: building the %s recipe" pkg r r;
      Recipe.install r;
      read_meta (r ^ ".uselink"))
    (Syslib.recipes pkg)

(* The C flags of the system recipes [pkg] uses (once built) *)
let system_cflags pkg = Compat.concat_map (fun r -> read_meta (r ^ ".usecflags")) (Syslib.recipes pkg)

(* -I flags for the lib/<dep> directories of the installed opam
   dependencies of [pkg] (not ocaml's: those of the host's runtime), where
   packages install the C headers of their stubs (integers:
   ocaml_integers.h, which ctypes's include) *)
let dep_includes pkg =
  match Switch.opam pkg with
  | None -> []
  | Some s ->
      Switch.entries (Switch.opam_field s "depends")
      |> List.map fst |> List.sort_uniq compare
      |> List.filter (fun d -> d <> "ocaml" && d <> "dune")
      |> List.filter_map (fun d ->
             let dir = Filename.concat (Switch.prefix ()) ("lib/" ^ d) in
             if Files.is_dir dir then Some ("-I" ^ dir) else None)

(* -I flags for the packages named in the opam file of [pkg] that install C
   headers in lib/<package> *)
let header_includes pkg =
  match Switch.opam pkg with
  | None -> []
  | Some s ->
      Switch.entries s |> List.map fst |> List.sort_uniq compare
      |> List.filter (fun d -> d <> "ocaml")
      |> List.filter_map (fun d ->
             let dir = Filename.concat (Switch.prefix ()) ("lib/" ^ d) in
             let headers = try Array.exists (fun f -> Filename.check_suffix f ".h") (Sys.readdir dir) with Sys_error _ -> false in
             if headers then Some ("-I" ^ dir) else None)

(* ----------------------------------------------------------- patched dune *)

(* A dune whose (ctypes) stanza links its generators as custom bytecode in
   a context without ocamlopt, as dune does for ppx drivers and cinaps
   (tools/dune/*.patch); the stock one links them natively only
   (ocaml/dune#13650), which the target's toolchain cannot.  Built from the
   sources of the switch's dune, once per version and patch; its path. *)
let patched_dune () =
  let bin = Env.sysroot_file "libexec/dune" and work = Env.sysroot_file "build/patched-dune" in
  let ver = match Switch.version "dune" with Some v -> v | None -> Env.fail "dune is not installed in %s" (Switch.prefix ()) in
  let patches = Filename.concat (Env.share ()) "tools/dune" in
  let files = Files.find patches (fun f -> Filename.check_suffix f ".patch") in
  let sum = Recipe.checksum (String.concat "" (List.map Compat.read_file files)) in
  let built = Sys.file_exists bin && Stamp.read "patched-dune" = Some [ ver; "patch=" ^ sum ] in
  if not built then (
    Source.remove work;
    Source.sh "mkdir" [ "-p"; Filename.dirname work ];
    ignore (Source.opam_source "dune" work);
    log "building dune %s, its (ctypes) stanza patched for the target's toolchain" ver;
    Source.remove (Filename.concat work "_build");
    Source.remove (Filename.concat work "_boot");
    let awk = Filename.concat (Env.share ()) "tools/patch.awk" in
    List.iter
      (fun p ->
        match Env.capture ~cwd:work ~errors:true "awk" [ "-f"; awk; p ] with
        | Some out ->
            let out = String.trim out in
            log "patch %s%s" (Filename.basename p) (if out = "" then "" else " (" ^ out ^ ")")
        | None -> Env.fail "patch %s failed" p)
      files;
    let path = "PATH=" ^ Env.host_bin () ^ ":" ^ Option.value (Env.getenv_opt "PATH") ~default:"" in
    if Env.run_logged ~cwd:work ~env:[ path ] (Filename.concat work "build.log") "make" [ "release" ] <> 0 then (
      ignore (Env.run ~out:Unix.stderr "tail" [ "-n"; "20"; Filename.concat work "build.log" ]);
      Env.fail "could not build the patched dune (log: %s/build.log)" work);
    Source.sh "mkdir" [ "-p"; Filename.dirname bin ];
    sh "cp" [ Filename.concat work "_build/install/default/bin/dune"; bin ];
    Stamp.write "patched-dune" [ ver; "patch=" ^ sum ];
    Source.remove work);
  bin

(* The dune that builds the package in [dir]: the patched one if it uses
   the (ctypes) stanza *)
let dune_for dir =
  let ctypes =
    Files.find ~skip:(Str_util.starts_with ~prefix:"_build") dir (( = ) "dune-project")
    |> List.exists (fun f -> Files.has_seq ~space:true (Files.contents f) "(using" [ "ctypes" ])
  in
  if ctypes then patched_dune () else Filename.concat (Env.host_bin ()) "dune"

(* The environment of dune building for the target: the driver's (the
   toolchain's ocamlc reads OCAML_EMCC_EXTRA_CFLAGS), what recipes run in,
   and bin/path first in PATH (ocamlmklib, pkg-config...) *)
let dune_env () =
  let path = Env.sysroot_file "bin/path" ^ ":" ^ Env.host_bin () ^ ":" ^ Option.value (Env.getenv_opt "PATH") ~default:"" in
  Toolchain.build_env ()
  @ [ "PATH=" ^ path; "OCAMLFIND_CONF=" ^ Env.sysroot_file "findlib.conf" ]
  @ List.filter (fun kv -> not (Str_util.starts_with ~prefix:"PATH=" kv)) (Driver.env ())

(* ------------------------------------------------------------ dune stubs *)

let lib_archive f = Str_util.starts_with ~prefix:"lib" f && Filename.check_suffix f ".a"
let archives dir = Files.find ~skip:Files.hidden dir (fun f -> lib_archive f && not (Files.hidden f))
let lib_name a = let b = Filename.chop_suffix (Filename.basename a) ".a" in String.sub b 3 (String.length b - 3)

(* For what dune cannot cross-compile, and the archives of `dune -x` holding
   host objects (see [dune_stubs]): each stub archive of the native build
   ([bdir]/default in [dir]; kept by OPAMKEEPBUILDDIR, else built here) is
   rebuilt with emcc from the C files behind its members: hand-written
   stubs, vendored C, and the C that ctypes generated (architecture
   independent).  The stubs' own C flags are not known: only -I flags are
   given (the file's directory and its source directory, the headers of the
   opam packages it depends on, those of the system recipes).  [only]: the
   archives to rebuild (lib<x>.a), all if empty.  The wasm archives. *)
let native_stubs ~dir ~bdir pkg only =
  let nat = Filename.concat dir (Filename.concat bdir "default") in
  (* (dune -x also makes _build/default, with only what the target needs) *)
  let missing =
    (not (Files.is_dir nat))
    || List.exists (fun x -> Files.first nat (( = ) x) = None) only
    || (only = [] && Files.first nat lib_archive = None)
  in
  if missing then (
    log "no native build kept for %s: building it" pkg;
    if Env.run ~cwd:dir ~out:Unix.stderr (Filename.concat (Env.host_bin ()) "dune") [ "build"; "--build-dir"; bdir; "-p"; pkg; "@install" ] <> 0
    then Env.fail "%s: native build failed" pkg);
  let incs = header_includes pkg @ system_cflags pkg in
  let out = Filename.concat dir "_wasm_stubs" in
  Source.sh "mkdir" [ "-p"; out ];
  archives nat
  |> List.filter (fun a -> only = [] || List.mem (Filename.basename a) only)
  |> List.map (fun a ->
         let adir = Filename.dirname a in
         let src_dir =
           let p = nat ^ "/" in
           if Str_util.starts_with ~prefix:p adir then Filename.concat dir (String.sub adir (String.length p) (String.length adir - String.length p))
           else adir
         in
         let objs =
           List.map
             (fun m ->
               let base = Filename.remove_extension m ^ ".c" in
               let c =
                 let c = Filename.concat adir base in
                 if Sys.file_exists c then c
                 else
                   (* (include_subdirs): the sources are in subdirectories *)
                   match Files.first ~skip:Files.hidden adir (( = ) base) with
                   | Some c -> c
                   | None -> Env.fail "%s: no C source for %s (in %s)" pkg m a
               in
               if not (compile ~cwd:dir ~flags:([ "-I" ^ Filename.dirname c; "-I" ^ adir; "-I" ^ src_dir ] @ incs) c) then
                 Env.fail "%s: cannot compile %s" pkg c;
               Filename.remove_extension c ^ ".o")
             (Archive.names a)
         in
         mklib out (lib_name a) objs)

(* In the sources of a dune package [dir], build its stub archives with
   `dune build -x` and install them, with the link flags of the system
   libraries it uses; whether there were any.  Also for recipes that patch
   a package before (`SOURCE=opam:PKG`, see mirage-crypto). *)
let dune_stubs ~dir ~provider pkg =
  if not (Sys.file_exists (Env.sysroot_file ("findlib.conf.d/" ^ !Env.target ^ ".conf"))) then Recipe.install "ocaml";
  let sysflags = system_deps pkg in
  log "building the C stubs of %s with dune -x %s" pkg !Env.target;
  (* The kept _build may be another tool's (lmdb is built with ocamlbuild,
     whose _build/install is a file): dune gets its own then. *)
  let b = Filename.concat dir "_build" in
  let bdir =
    if Sys.file_exists b && (not (Files.is_dir (Filename.concat b "default"))) && not (Sys.file_exists (Filename.concat b ".lock"))
    then "_build.dune"
    else "_build"
  in
  let dune = dune_for dir in
  let built =
    if
      Env.run ~cwd:dir ~env:(dune_env ()) ~out:Unix.stderr dune
        [ "build"; "--build-dir"; bdir; "-x"; !Env.target; "-p"; pkg; "@install" ]
      = 0
    then (
      let all = archives (Filename.concat dir (Filename.concat bdir ("default." ^ !Env.target))) in
      (* Archives made by a rule of the package with its own build system
         (ocaml-lua: `make` in the vendored Lua) hold host objects.  Those
         of stubs (with their dllX.so) are rebuilt, the others were
         intermediate. *)
      let wasm, host = List.partition Archive.is_wasm all in
      let host =
        List.filter
          (fun a ->
            let stub = Sys.file_exists (Filename.concat (Filename.dirname a) ("dll" ^ lib_name a ^ ".so")) in
            if not stub then log "  %s: host objects, not a stub archive: ignored" (Filename.basename a);
            stub)
          host
      in
      if host = [] then wasm
      else (
        log "host objects in %s: compiling the C files of the native build instead"
          (String.concat " " (List.map Filename.basename host));
        wasm @ native_stubs ~dir ~bdir pkg (List.map Filename.basename host)))
    else (
      log "dune -x %s failed: compiling the C files of the native build instead" !Env.target;
      native_stubs ~dir ~bdir pkg [])
  in
  List.iter
    (fun a ->
      let l = lib_name a in
      install_lib a;
      provides provider [ l ];
      if sysflags <> [] then link_flags l sysflags;
      log "  %s" (Filename.basename a))
    built;
  if built = [] then log "  (no C archive produced)";
  built <> []

(* Whether the stamp [name] is of the installed version of [pkg] *)
let up_to_date name pkg =
  match Stamp.read name, Switch.version pkg with Some f, Some v -> Stamp.version f = v | _ -> false

let stamp name version = Stamp.write name [ version; "emcc-" ^ Lazy.force Toolchain.emcc_version ]

(* Rebuild the stubs of the dune package [pkg] with its dune rules *)
let dune_package ?(force = false) pkg =
  let name = "dune-" ^ pkg in
  if force || not (up_to_date name pkg) then (
    let work = Env.sysroot_file ("build/" ^ name) in
    Source.remove work;
    Source.sh "mkdir" [ "-p"; Filename.dirname work ];
    let v = Source.opam_source pkg work in
    if not (dune_stubs ~dir:work ~provider:name pkg) then Env.fail "%s: no C archive built" pkg;
    stamp name v)

(* --------------------------------------------------------------- blindly *)

(* The C file of each member of a host archive, the one outside _build
   first; None if one has none *)
let archive_sources dir a =
  let found m =
    let c = Filename.remove_extension m ^ ".c" in
    match Files.first ~skip:(( = ) "_build") dir (( = ) c) with Some f -> Some f | None -> Files.first dir (( = ) c)
  in
  let members = List.filter (fun m -> Filename.check_suffix m ".o") (Archive.names a) in
  let files = List.map found members in
  if List.mem None files then None else Some (List.map Option.get files)

let includes_caml f =
  let s = Files.contents f in
  Files.has_seq s "#include" [ "<caml/"; "\"caml/" ]

(* Last resort for packages with neither a recipe nor dune.  If the kept
   native build has lib<lib>.a, the C files behind its members are compiled
   (glpk: with oldapi/lpx.c, which does not include the OCaml headers);
   otherwise every C file that includes the OCaml headers. *)
let auto ?(force = false) pkg lib =
  let name = Printf.sprintf "auto-%s-%s" pkg lib in
  if force || not (up_to_date name pkg) then (
    let sysflags = system_deps pkg in
    let cflags = system_cflags pkg @ dep_includes pkg in
    let work = Env.sysroot_file ("build/auto-" ^ pkg) in
    Source.remove work;
    Source.sh "mkdir" [ "-p"; Filename.dirname work ];
    let v = Source.opam_source pkg work in
    let native = Files.first work (( = ) ("lib" ^ lib ^ ".a")) in
    let files =
      match Option.map (archive_sources work) native with
      | Some (Some files) -> log "  the C files of the native lib%s.a" lib; files
      | _ -> (
          (* _build: the copies of the sources in the kept native build
             (ocamlbuild, topkg), only used when the stubs are nowhere else
             (generated) *)
          let c f = Filename.check_suffix f ".c" in
          match List.filter includes_caml (Files.find ~skip:(( = ) "_build") work c) with
          | [] -> List.filter includes_caml (Files.find work c)
          | l -> l)
    in
    if files = [] then Env.fail "%s: no OCaml stub found" pkg;
    let native_dir = match native with Some n -> Filename.dirname n | None -> work in
    let objs =
      List.map
        (fun f ->
          log "  emcc %s" f;
          if not (compile ~cwd:work ~flags:([ "-I" ^ Filename.dirname f; "-I" ^ native_dir ] @ cflags) f) then
            Env.fail "%s: cannot compile %s" pkg f;
          Filename.remove_extension f ^ ".o")
        files
    in
    install_lib (mklib work lib objs);
    provides ("auto-" ^ pkg) [ lib ];
    if sysflags <> [] then link_flags lib sysflags;
    stamp name v)

(* lib<lib>.a of the opam package [pkg], by the best available means: a
   recipe named after the package, the package's own dune rules, or a blind
   compilation of its stubs.  The recipe is built again if it was: the
   library is missing, or built for another version of the package. *)
let obtain pkg lib =
  (* not a system library recipe: the opam package `zlib` is the OCaml
     binding, not the C library *)
  let system r =
    List.exists (Str_util.starts_with ~prefix:"SOURCE=system:")
      (String.split_on_char '\n' (Files.contents (Recipe.script r)))
  in
  match Recipe.find pkg with
  | Some r when not (system r) -> Recipe.install ~force:true pkg
  | _ ->
      let probe = Env.sysroot_file ("build/probe-" ^ pkg) in
      Source.remove probe;
      Source.sh "mkdir" [ "-p"; Filename.dirname probe ];
      ignore (Source.opam_source pkg probe);
      let dune = Sys.file_exists (Filename.concat probe "dune-project") in
      Source.remove probe;
      if dune then dune_package pkg else auto pkg lib
