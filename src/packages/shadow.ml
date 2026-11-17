(* The OCaml libraries of a package, built for the target and installed in
   $SYSROOT/lib/findlib, which the toolchain searches before the switch.
   For ctypes and its users: ctypes lays C types out with the sizes it
   generated when it was built (ctypes_primitives.ml), and bindings
   generating their type descriptions (Cstubs_structs, dune's (ctypes)
   stanza) print the offsets of the structs from a C program: on the host,
   those of LP64.  The build has a single context on the target's
   toolchain, without the host context of `dune -x`, whose executables dune
   would run instead: OCaml generators are bytecode run by the host ocamlrun
   (with the host's stub DLLs), C ones are compiled by emcc and run by node
   (see the toolchain's emcc wrapper), dune-configurator gets the target's
   answers.
   For jst-config on wasm32 and the packages reading its config.h (Jane
   Street's): computed by dune-configurator, its word size is that of
   wasm32 once jst-config is built for it (JSC_ARCH_SIXTYFOUR undefined,
   see [merge_jst_config]), and the toolchain's
   %{lib:jst-config:config.h} is this one.

   The stamp shadow-<pkg> records the package version and the outcome: ok
   (installed), failed (it lays C types out or reads jst-config's
   configuration when built, and could not be rebuilt), none (it does not:
   the host's build is kept).  Rebuilt when the package changes version,
   or the toolchain's wrappers, or the patches of its recipe.
   Another package is only rebuilt if [needed]: it was compiled against
   interfaces that differ in the target's builds of its dependencies.  Otherwise the target's build of its libraries would
   differ from the host's for no reason, and so would be inconsistent with
   the packages depending on it, which keep the host's (frama-c's plugins,
   in other packages). *)

let log = Env.log

(* Whether the sources in [work] generate type descriptions with structs
   or unions (`seal`): zstd's only have constants *)
let computes_layouts work =
  let skip = Str_util.starts_with ~prefix:"_build" in
  let ml f = Filename.check_suffix f ".ml" in
  let generated s = List.exists (fun w -> Str_util.find s w <> None) [ "Cstubs_structs"; "Cstubs.Types"; "type_description" ] in
  List.exists (fun f -> generated (Files.contents f)) (Files.find ~skip work (fun f -> ml f || f = "dune"))
  && List.exists (fun f -> Files.has_word (Files.contents f) "seal") (Files.find ~skip work ml)

(* Whether [pkg], whose sources are in [work], is jst-config or reads its
   config.h in OCaml code, on wasm32 (the host's is that of 64 bits): its
   dune files copy %{lib:jst-config:config.h}, and ppx_optcomp imports it
   ([%%import "config.h"]; core copies it for its C stubs only) *)
let reads_jst_config pkg work =
  let skip = Str_util.starts_with ~prefix:"_build" in
  let has f s = Str_util.find (Files.contents f) s <> None in
  let ml f = List.exists (Filename.check_suffix f) [ ".ml"; ".mli"; ".mlh" ] in
  !Env.target = "wasm32"
  && (pkg = "jst-config"
     || List.exists (fun f -> has f "jst-config:config.h") (Files.find ~skip work (fun f -> f = "dune"))
        && List.exists (fun f -> has f "%%import") (Files.find ~skip work ml))

(* Whether [pkg], whose sources are in [work], chooses its OCaml code by
   the word size in its dune files, on wasm32 (the host's is 64 bits):
   rocq-runtime's uint63_%{ocaml-config:int_size}.ml *)
let reads_word_size work =
  let skip = Str_util.starts_with ~prefix:"_build" in
  let has s = List.exists (fun w -> Str_util.find s w <> None) [ "%{ocaml-config:int_size}"; "%{ocaml-config:word_size}"; "%{arch_sixtyfour}" ] in
  !Env.target = "wasm32" && List.exists (fun f -> has (Files.contents f)) (Files.find ~skip work (fun f -> f = "dune"))

(* The recipe.sh of [pkg], if it has a recipe *)
let recipe_text pkg = Option.map (fun d -> Files.contents (Recipe.script d)) (Recipe.find pkg)

let has_line s l = List.exists (fun x -> String.trim x = l) (String.split_on_char '\n' s)

(* Whether the recipe of [pkg] builds the OCaml libraries of [pkg] from its
   own sources (PATCH_OCAML=1 with SOURCE=git:, url: or dir:): a package
   the switch does not have (coq-lsp for Rocq 9.2, which opam lacks), or
   another version of one it has.  They are built for the target only. *)
let from_recipe pkg =
  match recipe_text pkg with
  | Some s ->
      has_line s "PATCH_OCAML=1"
      && List.exists
           (fun src -> List.exists (fun prefix -> Str_util.starts_with ~prefix src) [ "git:"; "url:"; "dir:" ])
           (Recipe.assignments s "SOURCE")
  | None -> false

(* Whether the recipe of [pkg] builds its opam sources (SOURCE=opam:PKG) *)
let opam_recipe pkg =
  match recipe_text pkg with Some s -> Str_util.find s ("SOURCE=opam:" ^ pkg) <> None | None -> false

(* The patches of the recipe of [pkg] that it is built with (core_unix's C
   stubs), if it has one for its opam sources or its own: patches/*.patch,
   as `apply_patches DIR` applies them (not the subdirectories, which its
   build chooses by version: raylib's until-2.3) *)
let patches pkg =
  match Recipe.find pkg with
  | Some d when opam_recipe pkg || from_recipe pkg ->
      let dir = Filename.concat d "patches" in
      (try Array.to_list (Sys.readdir dir) with Sys_error _ -> [])
      |> List.filter (fun f -> Filename.check_suffix f ".patch")
      |> List.sort compare
      |> List.map (Filename.concat dir)
  | _ -> []

(* Whether the recipe of [pkg] patches its OCaml libraries (PATCH_OCAML=1):
   they are then rebuilt for the target with its patches *)
let patches_ocaml pkg =
  match recipe_text pkg with
  | Some s -> (opam_recipe pkg && has_line s "PATCH_OCAML=1") || from_recipe pkg
  | None -> false

(* Whether the recipe of [pkg] has its build tools built for the host
   (HOST_TOOLS=1) when its OCaml libraries are rebuilt for the target *)
let host_tools pkg = match recipe_text pkg with Some s -> has_line s "HOST_TOOLS=1" | None -> false

(* The version of [pkg] its build for the target is from: the installed
   one, or "recipe-<checksum>" of a recipe with its own sources *)
let versions = Hashtbl.create 16

let version pkg =
  match Hashtbl.find_opt versions pkg with
  | Some v -> v
  | None ->
      let v = if from_recipe pkg then Some ("recipe-" ^ Recipe.sum pkg) else Switch.version pkg in
      Hashtbl.replace versions pkg v;
      v

(* The sources of [pkg], patched, in [work] *)
let prepare pkg work =
  Source.remove work;
  Source.sh "mkdir" [ "-p"; Filename.dirname work ];
  if from_recipe pkg then ignore (Recipe.fetch (Recipe.describe pkg) pkg work) else ignore (Source.opam_source pkg work);
  Stubs.apply_patches ~cwd:work (patches pkg)

(* The installed packages whose libraries the dune files of [work] name
   ((libraries ...), select forms included): the findlib packages of the
   switch, by the opam package that installed their META *)
let dune_deps pkg work =
  let skip = Str_util.starts_with ~prefix:"_build" in
  let names = Hashtbl.create 16 in
  List.iter
    (fun f ->
      let s = Files.contents f in
      let rec scan i =
        match Str_util.find_from s i "(libraries" with
        | None -> ()
        | Some a ->
            let depth = ref 1 and j = ref (a + 1) in
            while !j < String.length s && !depth > 0 do
              (match s.[!j] with '(' -> incr depth | ')' -> decr depth | _ -> ());
              incr j
            done;
            let body = String.sub s (a + 10) (!j - a - 10) in
            let blank c = if String.contains "()\n\t\r" c then ' ' else c in
            List.iter
              (fun w -> Hashtbl.replace names (List.hd (String.split_on_char '.' w)) ())
              (Str_util.words (String.map blank body));
            scan !j
      in
      scan 0)
    (Files.find ~skip work (fun f -> f = "dune"));
  Hashtbl.fold (fun n () acc -> n :: acc) names []
  |> List.filter_map (fun n ->
         let meta = Printf.sprintf "lib/%s/META" n in
         if n <> "" && Sys.file_exists (Filename.concat (Switch.prefix ()) meta) then Switch.owner meta else None)
  |> List.filter (fun d -> d <> pkg)
  |> List.sort_uniq compare

(* The dependencies of [pkg], built from the sources of its recipe, among
   the installed packages (no opam file to read them from): from its dune
   files, recorded for its version *)
let deps_file pkg = Stubs.meta ("shadow-" ^ pkg ^ ".deps")

let record_deps pkg work =
  Source.sh "mkdir" [ "-p"; Filename.dirname (deps_file pkg) ];
  Compat.write_file (deps_file pkg) (String.concat " " (Option.get (version pkg) :: dune_deps pkg work) ^ "\n")

let recipe_deps pkg =
  let read () =
    match Str_util.words (String.trim (Files.contents (deps_file pkg))) with
    | v :: ds when Some v = version pkg -> Some ds
    | _ -> None
  in
  match read () with
  | Some ds -> ds
  | None ->
      let work = Env.sysroot_file ("build/deps-" ^ pkg) in
      prepare pkg work;
      record_deps pkg work;
      Source.remove work;
      Option.value (read ()) ~default:[]

(* "patch=<checksum>" of [patches], in the stamp: a change builds it again *)
let patch_tag pkg =
  "patch=" ^ match patches pkg with [] -> "" | l -> Recipe.checksum (String.concat "" (List.map Compat.read_file l))

(* "dune=<version>" of the dune building it, in the stamp.  Its
   dune-package files say (lang dune <its version>), which an older dune
   cannot read: once dune downgraded (3.24 to 3.23, by a package's
   constraint), they are built again. *)
let dune_tag () = "dune=" ^ Option.value (Switch.version "dune") ~default:""

let dune_readable fields =
  match List.find_opt (Str_util.starts_with ~prefix:"dune=") fields with
  | None -> true
  | Some f ->
      let built = String.sub f 5 (String.length f - 5) and current = Option.value (Switch.version "dune") ~default:"" in
      Source.compare_versions built current <= 0

let findlib d = Env.sysroot_file (Filename.concat "lib/findlib" d)
let dirs_file pkg = Stubs.meta ("shadow-" ^ pkg ^ ".dirs")

(* jst-config's config.h for the target: the host's, but for the target's
   JSC_ARCH_* (word size, endianness).  The other answers of emscripten
   make combinations Jane Street's code never meets: JSC_LINUX_EXT
   without JSC_EVENTFD, where linux_ext declares eventfd's primitives in
   OCaml and defines them in C only with both.  core_unix's patches give
   the host's primitives to emscripten (ENOSYS). *)
let merge_jst_config () =
  let target = findlib "jst-config/config.h" in
  let host = Filename.concat (Switch.prefix ()) "lib/jst-config/config.h" in
  if Sys.file_exists target && Sys.file_exists host then (
    let lines f = String.split_on_char '\n' (Compat.read_file f) in
    let name l = match List.rev (Str_util.words l) with w :: _ -> w | [] -> "" in
    let arch l = Str_util.starts_with ~prefix:"JSC_ARCH_" (name l) in
    let target_arch = List.filter arch (lines target) in
    let merged =
      lines host
      |> List.map (fun l -> if arch l then Option.value (List.find_opt (fun t -> name t = name l) target_arch) ~default:l else l)
      |> String.concat "\n"
    in
    (* (copied from dune's _build, read-only) *)
    Unix.chmod target 0o644;
    Compat.write_file target merged)

let build ?(force = false) ?(needed = fun () -> true) ?(direct = true) pkg =
  let ver = match version pkg with Some v -> v | None -> Env.fail "%s is not installed in %s" pkg (Switch.prefix ()) in
  let name = "shadow-" ^ pkg in
  let built =
    match Stamp.read name with
    | Some f -> Stamp.version f = ver && Stamp.current_toolchain f && List.mem (patch_tag pkg) f && dune_readable f
    | None -> false
  in
  if force || not built then (
    (* the libraries of the previous version *)
    let dirs = dirs_file pkg in
    List.iter (fun d -> Source.remove (findlib d)) (Str_util.words (String.map (fun c -> if c = '\n' then ' ' else c) (Files.contents dirs)));
    (try Sys.remove dirs with Sys_error _ -> ());
    let work = Env.sysroot_file ("build/" ^ name) in
    Source.remove work;
    let own = from_recipe pkg in
    (* (without its sources when it does not depend on a root itself) *)
    let unneeded = lazy (not (needed ())) in
    let status = ref "none" in
    if (not direct) && Lazy.force unneeded then
      log "%s: the interfaces it was compiled against are the same for %s: not rebuilt" pkg !Env.target
    else (
      prepare pkg work;
      if own then record_deps pkg work;
      let layouts = computes_layouts work || reads_jst_config pkg work || reads_word_size work || patches_ocaml pkg in
      if layouts then status := "failed";
      if (not layouts) && Lazy.force unneeded then
        log "%s: nothing computed for the target, and the interfaces it was compiled against are the same for %s: not rebuilt" pkg !Env.target
      else if Sys.file_exists (Filename.concat work "dune-project") then (
        let dune = Stubs.dune_for work in
        ignore (Stubs.system_deps pkg);
        log "building the OCaml libraries of %s for %s" pkg !Env.target;
        (* (with a host context for the build tools the recipe asks for:
           rocq-runtime's configure.exe has C stubs, which a bytecode of the
           target's context cannot load; not by default, as the ctypes
           generators must run in the target's context) *)
        let host = host_tools pkg in
        Compat.write_file
          (Filename.concat work ".ocaml-emcc-workspace")
          (Printf.sprintf "(lang dune 3.0)\n%s(context (default (name default.%s) (toolchain %s)%s))\n"
             (if host then "(context default)\n" else "") !Env.target !Env.target (if host then " (host default)" else ""));
        let prefix = Switch.prefix () in
        let env = Stubs.dune_env () @ [ Printf.sprintf "CAML_LD_LIBRARY_PATH=%s/lib/stublibs:%s/lib/ocaml/stublibs" prefix prefix ] in
        let log_file = Filename.concat work "ocaml-emcc-build.log" in
        let lib = Filename.concat work ("_build.ocaml-emcc/install/default." ^ !Env.target ^ "/lib") in
        let has_cmi d = Files.first d (fun f -> Filename.check_suffix f ".cmi") <> None in
        (* (jst-config has none, only headers) *)
        let host_has_cmi = List.exists (fun f -> Filename.check_suffix f ".cmi") (Switch.lib_files pkg) in
        let built =
          Env.run_logged ~cwd:work ~env log_file dune
            ([ "build"; "--build-dir"; "_build.ocaml-emcc"; "--workspace"; ".ocaml-emcc-workspace" ]
            @ Switch.dune_selection pkg
            @ [ (if host then "@_build.ocaml-emcc/default." ^ !Env.target ^ "/install" else "@install") ])
          = 0
        in
        (* Failed for C alone (re2's vendored C++ library, janestreet_cpuid's
           x86 stubs): dune builds what it can, here every library of the
           host's, which is enough, its stubs being built apart (Stubs) *)
        let ocaml_files =
          lazy
            (List.filter (fun f -> Filename.check_suffix f ".cma" || Filename.check_suffix f ".cmi") (Switch.lib_files pkg)
            |> List.map (fun f -> String.sub f 4 (String.length f - 4)))
        in
        let complete () = Lazy.force ocaml_files <> [] && List.for_all (fun f -> Sys.file_exists (Filename.concat lib f)) (Lazy.force ocaml_files) in
        (* (from the recipe's sources: what built, coq-lsp's executables
           for jsoo failing) *)
        let ok = if own then built || has_cmi lib else (built || complete ()) && (has_cmi lib || not host_has_cmi) in
        if ok && not built then
          if own then log "  (some of its targets failed, log: %s)" log_file else log "  (its C failed: built apart)";
        if ok then (
          Source.sh "mkdir" [ "-p"; Env.sysroot_file "lib/findlib" ];
          (try List.sort compare (Array.to_list (Sys.readdir lib)) with Sys_error _ -> [])
          |> List.iter (fun d ->
                 let p = Filename.concat lib d in
                 (* (dune -p of a package that another build system builds
                    installs an empty library: hacl-star-raw, built by make
                    next to hacl-star) *)
                 if Files.is_dir p && d <> "stublibs" && (has_cmi p || not host_has_cmi) then (
                   Source.remove (findlib d);
                   Source.sh "cp" [ "-rL"; p; Env.sysroot_file "lib/findlib/" ];
                   let oc = open_out_gen [ Open_append; Open_creat ] 0o644 dirs in
                   output_string oc (d ^ "\n");
                   close_out oc;
                   log "  %s" (findlib d)));
          (* (its C failed: the stub archives its dune-package names, which
             dune requires, empty; `link` takes the sysroot's) *)
          if not built then
            Switch.lib_files pkg
            |> List.iter (fun f ->
                   let t = findlib (String.sub f 4 (String.length f - 4)) in
                   if Filename.check_suffix f ".a" && Files.is_dir (Filename.dirname t) && not (Sys.file_exists t) then
                     Compat.write_file t "!<arch>\n");
          if pkg = "jst-config" then merge_jst_config ();
          status := "ok")
        else (
          (* (needed: it lays C types out, or was compiled against an
             interface that differs for the target) *)
          status := "failed";
          ignore (Env.run ~out:Unix.stderr "tail" [ "-n"; "30"; log_file ]);
          log "%s: could not be built for %s (log: %s)" pkg !Env.target log_file)));
    Stamp.write name [ ver; !status; "emcc-" ^ Lazy.force Toolchain.emcc_version; Stamp.toolchain; patch_tag pkg; dune_tag () ])
