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

   The stamp shadow-<pkg> records the package version and the outcome: ok
   (installed), failed (it lays C types out when built, and could not be
   rebuilt), none (it does not: the host's build is kept).  Rebuilt when the
   package changes version. *)

let log = Env.log

(* Whether the sources in [work] generate type descriptions with structs
   or unions (`seal`): zstd's only have constants *)
let computes_layouts work =
  let skip = Str_util.starts_with ~prefix:"_build" in
  let ml f = Filename.check_suffix f ".ml" in
  let generated s = List.exists (fun w -> Str_util.find s w <> None) [ "Cstubs_structs"; "Cstubs.Types"; "type_description" ] in
  List.exists (fun f -> generated (Files.contents f)) (Files.find ~skip work (fun f -> ml f || f = "dune"))
  && List.exists (fun f -> Files.has_word (Files.contents f) "seal") (Files.find ~skip work ml)

let findlib d = Env.sysroot_file (Filename.concat "lib/findlib" d)
let dirs_file pkg = Stubs.meta ("shadow-" ^ pkg ^ ".dirs")

let build ?(force = false) pkg =
  let ver = match Switch.version pkg with Some v -> v | None -> Env.fail "%s is not installed in %s" pkg (Switch.prefix ()) in
  let name = "shadow-" ^ pkg in
  let built = match Stamp.read name with Some f -> Stamp.version f = ver | None -> false in
  if force || not built then (
    (* the libraries of the previous version *)
    let dirs = dirs_file pkg in
    List.iter (fun d -> Source.remove (findlib d)) (Str_util.words (String.map (fun c -> if c = '\n' then ' ' else c) (Files.contents dirs)));
    (try Sys.remove dirs with Sys_error _ -> ());
    let work = Env.sysroot_file ("build/" ^ name) in
    Source.remove work;
    Source.sh "mkdir" [ "-p"; Filename.dirname work ];
    ignore (Source.opam_source pkg work);
    let layouts = computes_layouts work in
    let status = ref (if layouts then "failed" else "none") in
    if Sys.file_exists (Filename.concat work "dune-project") then (
      let dune = Stubs.dune_for work in
      ignore (Stubs.system_deps pkg);
      log "building the OCaml libraries of %s for %s (C layouts of %s)" pkg !Env.target !Env.target;
      Compat.write_file
        (Filename.concat work ".ocaml-emcc-workspace")
        (Printf.sprintf "(lang dune 3.0)\n(context (default (name default.%s) (toolchain %s)))\n" !Env.target !Env.target);
      let prefix = Switch.prefix () in
      let env = Stubs.dune_env () @ [ Printf.sprintf "CAML_LD_LIBRARY_PATH=%s/lib/stublibs:%s/lib/ocaml/stublibs" prefix prefix ] in
      let log_file = Filename.concat work "ocaml-emcc-build.log" in
      let lib = Filename.concat work ("_build.ocaml-emcc/install/default." ^ !Env.target ^ "/lib") in
      let has_cmi d = Files.first d (fun f -> Filename.check_suffix f ".cmi") <> None in
      let ok =
        Env.run_logged ~cwd:work ~env log_file dune
          [ "build"; "--build-dir"; "_build.ocaml-emcc"; "--workspace"; ".ocaml-emcc-workspace"; "-p"; pkg; "@install" ]
        = 0
        && has_cmi lib
      in
      if ok then (
        Source.sh "mkdir" [ "-p"; Env.sysroot_file "lib/findlib" ];
        (try List.sort compare (Array.to_list (Sys.readdir lib)) with Sys_error _ -> [])
        |> List.iter (fun d ->
               let p = Filename.concat lib d in
               (* (dune -p of a package that another build system builds
                  installs an empty library: hacl-star-raw, built by make
                  next to hacl-star) *)
               if Files.is_dir p && d <> "stublibs" && has_cmi p then (
                 Source.remove (findlib d);
                 Source.sh "cp" [ "-rL"; p; Env.sysroot_file "lib/findlib/" ];
                 let oc = open_out_gen [ Open_append; Open_creat ] 0o644 dirs in
                 output_string oc (d ^ "\n");
                 close_out oc;
                 log "  %s" (findlib d)));
        status := "ok")
      else if layouts then (
        ignore (Env.run ~out:Unix.stderr "tail" [ "-n"; "30"; log_file ]);
        log "%s: could not be built for %s (log: %s)" pkg !Env.target log_file)
      else log "  not built for %s, which it does not need: no structs in its generated types" !Env.target);
    Stamp.write name [ ver; !status; "emcc-" ^ Lazy.force Toolchain.emcc_version ])
