open Ocaml_emcc

let usage =
  {|ocaml-emcc: OCaml programs with C stubs -> WebAssembly (emscripten)

usage: ocaml-emcc [GLOBAL OPTIONS] COMMAND ...

main command (dune projects):
  build OUT.js [--exe DIR/NAME] [LINK OPTIONS] [-- EMCC-ARGS...]
      Does everything: wasm runtime (first time), recipes required by
      ocaml-emcc.conf, the bytecode of the dune executable named like OUT
      (or --exe), its C stubs and those of its dependencies, the final link.
      OUT.js (+ OUT.wasm) runs in node and in browsers.  OUT.html adds an
      emscripten HTML page; OUT.wasm alone is a standalone module without the
      JavaScript glue (it imports emscripten functions, see --wasi).

link options (build and link):
  -L DIR          search lib<x>.a in DIR
  -l LIB          extra library or archive to link (repeatable)
  --preload       bytecode in a separate .data file instead of embedded
  --node-fs       node only: real file system access, .bc next to OUT.js
  -O FLAG         emcc optimisation flag (default -O2)
  --stack-size S  C stack size (default 8MB)
  --no-deps       do not build missing stub libraries automatically
  --wasi          OUT.wasm for a WASI host (wasmtime, node:wasi...): files,
                  clocks, sleep... on WASI instead of emscripten's JS (wasm32)
  --compiled      compile the bytecode to C with c_of_ocaml instead of
                  interpreting it (faster; wasm32, OCaml >= 4.14, no effects)
  --emcc-flag F   extra emcc link flag (repeatable); also everything after
                  `--`, $OCAML_EMCC_LDFLAGS and `link-flags:` in ocaml-emcc.conf

step by step (scripts, Makefiles, projects without dune):
  setup [--force]              build the wasm runtime of the switch's compiler
  install [--force] RECIPE...  build recipes (gmp, zarith, project recipes...)
  dune [DUNE-BUILD-ARGS...]    dune build -x <target> + static stub archives
  deps PROG.bc [-L DIR]...     build the missing stub libraries of PROG.bc
  doctor PROG.bc [-L DIR]...   stub libraries, primitives, 31-bit literals
  link PROG.bc -o OUT.js [LINK OPTIONS] [-- EMCC-ARGS...]
  env [--cflags|--sysroot]     paths and configuration; --cflags prints the
                               flags to compile C stubs with emcc

global options:
  --target wasm32|wasm64  wasm32 (default): 31-bit ints at run time, integer
                          literals >= 2^30 are wrapped (link/doctor warn),
                          arithmetic beyond 31 bits wraps silently.
                          wasm64: memory64, the semantics of the 64-bit host
  --switch SW             opam switch (default: the current one)
  --sysroot DIR           where wasm artifacts go (default: <switch>/emcc-sysroot/<target>)
  --recipes DIR           extra recipe directory (repeatable)
  -v                      show the commands run

A project can have an ocaml-emcc.conf (target, recipes, requires, link-flags,
cflags) and an emcc-recipes/ directory, found from the current directory.
|}

let die_usage () = prerr_string usage; exit 2

let rec global = function
  | "--switch" :: s :: rest -> Env.switch := Some s; global rest
  | "--sysroot" :: s :: rest -> Env.sysroot_override := Some s; global rest
  | "--target" :: (("wasm32" | "wasm64") as t) :: rest ->
      Env.target := t; Env.target_explicit := true; global rest
  | "--recipes" :: d :: rest ->
      let d = if Filename.is_relative d then Filename.concat (Sys.getcwd ()) d else d in
      Env.recipe_dirs := !Env.recipe_dirs @ [ d ]; global rest
  | ("-v" | "--verbose") :: rest -> Env.verbose := true; global rest
  | rest -> rest

let force args = match args with "--force" :: rest -> (true, rest) | _ -> (false, args)

let ensure_setup () =
  if not (Env.toolchain_ready ()) then (
    Env.log "no wasm runtime yet for this switch and target, building it (once)";
    if Env.driver [ "install"; "ocaml" ] <> 0 then Env.fail "setup failed")
  else if Env.manifest "toolchain" <> Some Env.toolchain_version then (
    Env.log "updating the toolchain wrappers of %s" (Env.sysroot ());
    if Env.driver [ "toolchain" ] <> 0 then Env.fail "toolchain update failed")

(* `requires:` of ocaml-emcc.conf (no-op once built: recipes are stamped) *)
let ensure_requires () =
  ensure_setup ();
  match (Project.get ()).requires with
  | [] -> ()
  | rs -> if Env.driver ("install" :: rs) <> 0 then Env.fail "could not build %s" (String.concat " " rs)

let cmd_setup args =
  let f, _ = force args in
  exit (Env.driver ([ "install" ] @ (if f then [ "--force" ] else []) @ [ "ocaml" ]))

let cmd_install args =
  let f, recipes = force args in
  if recipes = [] then die_usage ();
  ensure_setup ();
  exit (Env.driver ([ "install" ] @ (if f then [ "--force" ] else []) @ recipes))

(* ------------------------------------------------------------------ dune *)

(* dune's (ctypes) stanza links its generators natively only, which the wasm
   context cannot (no ocamlopt, ocaml/dune#13650): a project using it is
   built by a patched dune (driver.sh patched_dune). *)
let patched_dune =
  lazy (match Env.driver_output [ "patched-dune" ] with Some d -> d | None -> Env.fail "could not build the patched dune")

let uses_ctypes_stanza root =
  match Compat.read_file (Filename.concat root "dune-project") with
  | s -> Str_util.find s "(using ctypes" <> None
  | exception Sys_error _ -> false

let dune_bin ~root =
  if uses_ctypes_stanza root then Lazy.force patched_dune
  else
    let d = Filename.concat (Env.host_bin ()) "dune" in
    if Sys.file_exists d then d else "dune"

(* bin/path first in PATH: rules running `ocamlmklib` themselves get the wasm one *)
let dune_env () =
  let bin_path = Env.sysroot_file "bin/path" in
  ("OCAMLFIND_CONF=" ^ Env.sysroot_file "findlib.conf")
  :: List.map
       (fun kv -> if Str_util.starts_with ~prefix:"PATH=" kv then "PATH=" ^ bin_path ^ ":" ^ String.sub kv 5 (String.length kv - 5) else kv)
       (Env.driver_env ())

let ctx_dir () = "_build/default." ^ !Env.target

(* Linking a .bc only needs the (placeholder) dll<x>.so of the stubs, so dune
   does not build the static lib<x>.a: request them explicitly. *)
let build_stub_archives ~root =
  let ctx = Filename.concat root (ctx_dir ()) in
  let archives = ref [] in
  let rec walk rel =
    let dir = Filename.concat ctx rel in
    match Sys.readdir dir with
    | exception Sys_error _ -> ()
    | entries ->
        Array.iter
          (fun e ->
            let r = if rel = "" then e else Filename.concat rel e in
            if e.[0] <> '.' && Sys.is_directory (Filename.concat dir e) then walk r
            else if Str_util.starts_with ~prefix:"dll" e && Filename.check_suffix e ".so" then
              let lib = "lib" ^ Filename.chop_suffix (String.sub e 3 (String.length e - 3)) ".so" ^ ".a" in
              archives := Filename.concat (ctx_dir ()) (Filename.concat (Filename.dirname r) lib) :: !archives)
          entries
  in
  walk "";
  if !archives = [] then 0
  else Env.run ~env:(dune_env ()) (dune_bin ~root) ("build" :: "-x" :: !Env.target :: "--root" :: root :: !archives)

let cmd_dune args =
  ensure_requires ();
  let rec root = function "--root" :: r :: _ -> r | _ :: rest -> root rest | [] -> "." in
  let root = root args in
  let code = Env.run ~env:(dune_env ()) (dune_bin ~root) ("build" :: "-x" :: !Env.target :: args) in
  if code <> 0 then exit code;
  exit (build_stub_archives ~root)

(* ------------------------------------------------------------ link options *)

let default_link_opts : Link.opts =
  {
    bc = ""; output = ""; lib_dirs = []; libs = []; emcc_flags = []; mode = Link.Embed;
    opt = "-O2"; stack_size = "8MB"; auto_deps = true; check = true; wasi = false; compiled = false;
  }

(* Options shared by `link` and `build`; [extra] handles command-specific
   ones, positional arguments are returned in order. *)
let parse_link_opts ?(extra = fun _ -> None) args =
  let rec go (o : Link.opts) pos = function
    | "-L" :: d :: rest -> go { o with lib_dirs = o.lib_dirs @ [ d ] } pos rest
    | "-l" :: l :: rest ->
        let l = if Filename.check_suffix l ".a" || Filename.check_suffix l ".o" then l else "-l" ^ l in
        go { o with libs = o.libs @ [ l ] } pos rest
    | "--preload" :: rest -> go { o with mode = Link.Preload } pos rest
    | "--node-fs" :: rest -> go { o with mode = Link.Node_rawfs } pos rest
    | "-O" :: f :: rest -> go { o with opt = f } pos rest
    | "--stack-size" :: s :: rest -> go { o with stack_size = s } pos rest
    | "--no-deps" :: rest -> go { o with auto_deps = false } pos rest
    | "--wasi" :: rest -> go { o with wasi = true } pos rest
    | "--compiled" :: rest -> go { o with compiled = true } pos rest
    | "--emcc-flag" :: f :: rest -> go { o with emcc_flags = o.emcc_flags @ [ f ] } pos rest
    | "--" :: rest -> ({ o with emcc_flags = o.emcc_flags @ rest }, List.rev pos)
    | l -> (
        match extra l with
        | Some (f, rest) -> go (f o) pos rest
        | None -> (
            match l with
            | x :: rest when not (Str_util.starts_with ~prefix:"-" x) -> go o (x :: pos) rest
            | [] -> (o, List.rev pos)
            | x :: _ -> Env.fail "unexpected argument %s" x))
  in
  go default_link_opts [] args

(* lowest to highest precedence: ocaml-emcc.conf, $OCAML_EMCC_LDFLAGS,
   command line (emcc keeps the last -s setting) *)
let with_config_flags (o : Link.opts) =
  let env_flags = Option.fold ~none:[] ~some:Str_util.words (Env.getenv_opt "OCAML_EMCC_LDFLAGS") in
  { o with emcc_flags = (Project.get ()).link_flags @ env_flags @ o.emcc_flags }

let cmd_link args =
  let out = ref "" in
  let extra = function "-o" :: f :: rest -> out := f; Some (Fun.id, rest) | _ -> None in
  match parse_link_opts ~extra args with
  | o, [ bc ] when !out <> "" ->
      ensure_requires ();
      Link.run (with_config_flags { o with bc; output = !out })
  | _ -> die_usage ()

(* ----------------------------------------------------------------- build *)

let absolute p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

(* "a/b/../c" -> "a/c", for comparing paths *)
let normalize p =
  let parts = String.split_on_char '/' p in
  let rec go acc = function
    | [] -> List.rev acc
    | ("" | ".") :: r when acc <> [] -> go acc r
    | ".." :: r -> go (match acc with _ :: a when acc <> [ "" ] -> a | a -> a) r
    | x :: r -> go (x :: acc) r
  in
  String.concat "/" (go [] parts)

let relative_to root p =
  let root = normalize root ^ "/" and p = normalize p in
  if Str_util.starts_with ~prefix:root p then Some (String.sub p (String.length root) (String.length p - String.length root))
  else None

(* The dune executable to build for OUT: --exe, else the executable at the
   same place in the project (bin/main.js -> bin/main), else the only
   executable of the project with that name. *)
let find_exe ~root ~exe out =
  match exe with
  | Some e -> e
  | None ->
      let name = Filename.remove_extension (Filename.basename out) in
      let exes = Describe.run ~dune:(dune_bin ~root) ~root in
      let candidates = List.filter (fun (e : Describe.exe) -> List.mem name e.names) exes in
      let same_place =
        match relative_to root (absolute out) with
        | Some rel ->
            let dir = Filename.dirname rel in
            List.find_opt (fun (e : Describe.exe) -> e.dir = dir) candidates
        | None -> None
      in
      let path (e : Describe.exe) = if e.dir = "." then name else Filename.concat e.dir name in
      (match (same_place, candidates) with
      | Some e, _ -> path e
      | None, [ e ] -> path e
      | None, [] ->
          let all = Compat.concat_map (fun (e : Describe.exe) -> List.map (fun n -> Filename.concat e.dir n) e.names) exes in
          Env.fail "no dune executable named %s in %s%s.\n  Use --exe DIR/NAME." name root
            (if all = [] then "" else " (executables: " ^ String.concat ", " all ^ ")")
      | None, l ->
          Env.fail "several executables are named %s: %s.\n  Use --exe DIR/NAME." name
            (String.concat ", " (List.map path l)))

let cmd_build args =
  let exe = ref None in
  let extra = function "--exe" :: e :: rest -> exe := Some e; Some (Fun.id, rest) | _ -> None in
  let o, out = match parse_link_opts ~extra args with o, [ out ] -> (o, out) | _ -> die_usage () in
  let root =
    match Project.find_up (Sys.getcwd ()) [ "dune-project" ] with
    | Some (d, _) -> d
    | None -> Env.fail "no dune-project found from %s.\n  Without dune, use the step by step commands (ocaml-emcc link PROG.bc -o OUT.js)." (Sys.getcwd ())
  in
  ensure_requires ();
  let exe =
    let e = find_exe ~root ~exe:!exe out in
    if Filename.check_suffix e ".bc" || Filename.check_suffix e ".exe" then Filename.remove_extension e else e
  in
  (* In the wasm context, X.bc exists for (modes byte), and X.exe is also
     plain bytecode there (the ocamlc wrapper turns byte_complete into it). *)
  let dune = dune_bin ~root and env = dune_env () in
  let target ext = Filename.concat (ctx_dir ()) (exe ^ ext) in
  let layouts = o.auto_deps in
  if layouts then Layouts.prune ();
  let rec build_bc tries =
    let errs = Buffer.create 256 in
    let try_build ext =
      let code, err = Env.run_capture_stderr ~env dune [ "build"; "-x"; !Env.target; "--root"; root; target ext ] in
      Buffer.add_string errs err;
      if code = 0 then (prerr_string err; Some (target ext)) else (if ext = ".exe" then prerr_string err; None)
    in
    Env.log "building %s (dune -x %s)" exe !Env.target;
    match try_build ".bc" with
    | Some t -> t
    | None -> (
        match try_build ".exe" with
        | Some t -> t
        | None ->
            (* a library of the switch compiled against the host's build of
               a package rebuilt for the target (ctypes-foreign and ctypes) *)
            if tries > 0 && layouts && Layouts.fix_inconsistent (Buffer.contents errs) then build_bc (tries - 1)
            else Env.fail "dune could not build %s" exe)
  in
  let built = build_bc 5 in
  (* ctypes and its users built for the target (C layouts), then the
     bytecode again, against them *)
  let built =
    if not layouts then built
    else
      let bc = Bytecode.parse (Filename.concat root built) in
      let installed = Layouts.ensure bc in
      if installed || List.exists (fun (_, s) -> s = Layouts.Stale) (Layouts.states bc) then (
        Env.log "rebuilding %s against the %s builds of its ctypes libraries" exe !Env.target;
        build_bc 5)
      else built
  in
  if build_stub_archives ~root <> 0 then Env.fail "dune could not build the stub archives";
  Link.run (with_config_flags { o with bc = Filename.concat root built; output = out })

(* ------------------------------------------------------- deps / doctor *)

let parse_bc_and_dirs args =
  let rec go bc dirs = function
    | "-L" :: d :: rest -> go bc (d :: dirs) rest
    | x :: rest when bc = None -> go (Some x) dirs rest
    | [] -> (bc, List.rev dirs)
    | _ -> die_usage ()
  in
  match go None [] args with Some bc, dirs -> (bc, dirs) | None, _ -> die_usage ()

let cmd_deps args =
  ensure_requires ();
  let bc_path, dirs = parse_bc_and_dirs args in
  let bc = Bytecode.parse bc_path in
  Link.check_magic ~bc_path bc;
  ignore (Link.resolve_libs ~extra_dirs:dirs ~auto_deps:true ~bc_path bc);
  Env.log "all stub libraries of %s are available" bc_path

let cmd_doctor args =
  let bc_path, dirs = parse_bc_and_dirs args in
  let bc = Bytecode.parse bc_path in
  Link.check_magic ~bc_path bc;
  let prims = Bytecode.primitives bc in
  Printf.printf "%s: %d primitives, %d stub DLLs\n" bc_path (List.length prims) (List.length (Bytecode.dlls bc));
  (match Link.literals_report bc with
  | `Ok -> print_endline "integer literals: all fit in 31 bits (ok for wasm32)"
  | `Unknown why -> Printf.printf "integer literals: could not check (%s)\n" why
  | `Large l ->
      Printf.printf
        "WARNING: %d integer literal(s) do not fit in 31 bits: %s\n\
        \  -> on wasm32 they are wrapped to 31 bits when the program starts, as\n\
        \     32-bit OCaml would; fine on wasm64.\n"
        (List.length l) (Link.show_literals l));
  List.iter
    (fun (p, s) ->
      let t = !Env.target in
      Printf.printf "C layouts of %s: %s\n" p
        (match s with
        | Layouts.Rebuilt -> t ^ " (ok)"
        | Layouts.Stale -> "WARNING: the 64-bit host's; rebuild the bytecode against its " ^ t ^ " build"
        | Layouts.Not_rebuilt -> "WARNING: the 64-bit host's, no " ^ t ^ " build (`link` tries one)"
        | Layouts.Unneeded -> "none computed when it was built (ok)"))
    (Layouts.states bc);
  let found = ref [ Env.sysroot_file "lib/libcamlrun.a" ] in
  List.iter
    (fun d ->
      let name = Bytecode.lib_of_dll d in
      match Deps.resolve ~extra_dirs:dirs ~bc_path bc name with
      | Deps.Found f -> found := f :: !found; Printf.printf "  %-24s ok       %s\n" d f
      | Deps.Missing (Some p) -> Printf.printf "  %-24s MISSING  build with: ocaml-emcc deps (opam package %s)\n" d p
      | Deps.Missing None -> Printf.printf "  %-24s MISSING\n" d
      | Deps.Local _ -> Printf.printf "  %-24s MISSING  project stubs? run: ocaml-emcc dune\n" d)
    (Bytecode.dlls bc);
  if Sys.file_exists (List.hd (List.rev !found)) then (
    let syms = Link.defined_symbols !found in
    let missing = List.filter (fun p -> not (Hashtbl.mem syms p)) prims in
    if missing = [] then print_endline "all primitives are defined"
    else Printf.printf "undefined primitives (%d):\n  %s\n" (List.length missing) (String.concat "\n  " missing))
  else print_endline "(no wasm runtime yet: run ocaml-emcc setup)"

(* ------------------------------------------------------------------- env *)

let stub_cflags () =
  Env.manifest_flags "cflags"
  @ [ "-I" ^ Env.sysroot_file "lib/ocaml"; "-I" ^ Env.sysroot_file "include"; "-D_FILE_OFFSET_BITS=64" ]
  @ (Project.get ()).cflags
  @ Option.fold ~none:[] ~some:Str_util.words (Env.getenv_opt "OCAML_EMCC_EXTRA_CFLAGS")

let cmd_env = function
  | [ "--cflags" ] -> ensure_setup (); print_endline (String.concat " " (stub_cflags ()))
  | [ "--sysroot" ] -> print_endline (Env.sysroot ())
  | [] ->
      let p = Project.get () in
      Printf.printf "project        : %s\nproject recipes: %s\nrequires       : %s\n"
        (Option.value p.dir ~default:"(none)") (String.concat " " p.recipes) (String.concat " " p.requires);
      Printf.printf "target         : %s\nswitch prefix  : %s\nsysroot        : %s\nshare          : %s\nemcc           : %s\nruntime ready  : %b\n"
        !Env.target (Lazy.force Env.switch_prefix) (Env.sysroot ()) (Env.share ())
        (Option.value (Env.which "emcc") ~default:"(not found)")
        (Env.toolchain_ready ());
      let m = Env.sysroot_file "manifest" in
      if Sys.file_exists m then print_string (Bytecode.read_file m)
  | _ -> die_usage ()

let () =
  let args = global (List.tl (Array.to_list Sys.argv)) in
  (match (Project.get ()).target with
  | Some (("wasm32" | "wasm64") as t) when not !Env.target_explicit -> Env.target := t
  | Some t when not !Env.target_explicit -> Env.fail "ocaml-emcc.conf: unknown target %s" t
  | _ -> ());
  match args with
  | "build" :: args -> cmd_build args
  | "setup" :: args -> cmd_setup args
  | "install" :: args -> cmd_install args
  | "dune" :: args -> cmd_dune args
  | "deps" :: args -> cmd_deps args
  | "doctor" :: args -> cmd_doctor args
  | "link" :: args -> cmd_link args
  | "env" :: args -> cmd_env args
  | ("help" | "-h" | "--help") :: _ -> print_string usage
  | _ -> die_usage ()
