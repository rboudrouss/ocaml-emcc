(* --docker (prototype, wasm32): the bytecode compiled by a 32-bit OCaml in
   a container.  Everything a library computes when it is built (ctypes'
   sizes and struct offsets, dune-configurator's answers, integer literals,
   Sys.word_size) is then that of a 32-bit platform, as the wasm32 runtime
   is, instead of the 64-bit host's.

   - linux/arm/v7 (default): the C layouts of wasm32, but for long double
     (8 bytes, 16 on wasm32).  On an x86 host, it runs under qemu-user
     (binfmt_misc), slowly.
   - linux/386: no emulation, but i386 aligns double and int64_t to 4 bytes
     in structs (wasm32: 8).

   The image has an opam switch with the OCaml version of the host's switch
   and the host's version of every package the program uses (found from its
   host-built bytecode and `dune describe external-lib-deps`), installed on
   demand and committed to the image.  The C stubs are still the host's,
   rebuilt for wasm32: same versions, same primitives. *)

let platform = ref "linux/arm/v7"

(* a tag-friendly name: linux/arm/v7 -> arm-v7 *)
let arch () =
  let p = !platform in
  let p = if Str_util.starts_with ~prefix:"linux/" p then String.sub p 6 (String.length p - 6) else p in
  String.map (fun c -> if c = '/' then '-' else c) p

(* i386 userland on an x86_64 kernel: uname says x86_64, which would make
   OCaml's configure build a 64-bit compiler *)
let linux32 () = if arch () = "386" then [ "linux32" ] else []

let ocaml_version () =
  match Env.output_of (Filename.concat (Env.host_bin ()) "ocamlc") [ "-vnum" ] with
  | Some v -> v
  | None -> Env.fail "cannot run the switch's ocamlc"

let image () = Printf.sprintf "ocaml-emcc-docker:%s-%s" (arch ()) (ocaml_version ())

let docker args = Env.run "docker" args

let docker_exn what args = if docker args <> 0 then Env.fail "docker: %s failed" what

let check_docker () =
  if Env.which "docker" = None then Env.fail "--docker: docker not found in PATH";
  let cpu = Option.value (Env.output_of "uname" [ "-m" ]) ~default:"" in
  if arch () <> "386" && cpu <> "armv7l" && cpu <> "aarch64" then (
    (* binfmt_misc entry of qemu-user for ARM *)
    let entries = try Array.to_list (Sys.readdir "/proc/sys/fs/binfmt_misc") with Sys_error _ -> [] in
    if not (List.exists (fun e -> Str_util.find e "arm" <> None) entries) then
      Env.fail
        "--docker: %s containers need an ARM emulator on this %s machine (qemu-user in binfmt_misc).\n\
        \  Install it with: docker run --privileged --rm tonistiigi/binfmt --install arm\n\
        \  (Docker Desktop has it), or use --docker-platform linux/386 (no emulation, but\n\
        \  double and int64_t are aligned to 4 bytes in structs there)." !platform cpu)

(* The compiler package of the host's switch *)
let compiler () =
  match Layouts.version "ocaml-base-compiler" with
  | Some v -> "ocaml-base-compiler." ^ v
  | None -> Env.fail "--docker: only switches with ocaml-base-compiler are supported (prototype)"

let base_image () =
  let img = image () in
  if Env.output_of "docker" [ "image"; "inspect"; "--format"; "{{.Id}}"; img ] = None then (
    Env.log "--docker: building the image %s (debian, opam, %s), once" img (compiler ());
    let dir = Filename.concat (Filename.get_temp_dir_name ()) ("ocaml-emcc-docker-" ^ string_of_int (Unix.getpid ())) in
    (try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
    let l32 = String.concat " " (linux32 ()) in
    Compat.write_file (Filename.concat dir "Dockerfile")
      (Printf.sprintf
         "FROM --platform=%s debian:trixie\n\
          RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \\\n\
         \  opam build-essential m4 pkg-config git rsync unzip curl ca-certificates patch bzip2 xz-utils\n\
          ENV OPAMROOT=/opt/opam OPAMYES=1 OPAMCONFIRMLEVEL=unsafe-yes OPAMDEPEXTYES=1\n\
          RUN %s opam init --bare --disable-sandboxing -n default https://opam.ocaml.org \\\n\
         \ && %s opam switch create default %s && chmod -R a+rX /opt/opam\n\
          ENV OPAM_SWITCH_PREFIX=/opt/opam/default PATH=/opt/opam/default/bin:/usr/local/bin:/usr/bin:/bin \\\n\
         \  CAML_LD_LIBRARY_PATH=/opt/opam/default/lib/stublibs:/opt/opam/default/lib/ocaml/stublibs:/opt/opam/default/lib/ocaml\n"
         !platform l32 l32 (compiler ()));
    docker_exn "image build" [ "build"; "--platform"; !platform; "-t"; img; dir ])

(* installed packages of the image: name -> version *)
let image_packages () =
  let out =
    Env.output_of "docker"
      [ "run"; "--rm"; "--platform"; !platform; image (); "opam"; "list"; "--installed"; "--short"; "--columns=name,version" ]
  in
  List.filter_map
    (fun l -> match Str_util.words l with [ n; v ] -> Some (n, v) | _ -> None)
    (String.split_on_char '\n' (Option.value out ~default:""))

(* Packages that describe the host, not something to install *)
let host_only p =
  List.exists (fun prefix -> Str_util.starts_with ~prefix p) [ "host-arch-"; "host-system-"; "arch-"; "ocaml-emcc" ]

(* The opam packages behind the modules of [bc] and the external libraries
   of the project (ppx included), with their dependencies. *)
let packages ~root bc =
  let installed = Lazy.force Layouts.installed in
  let crcs = Bytecode.crcs bc in
  let all = Hashtbl.fold (fun p _ acc -> p :: acc) installed [] |> List.sort compare in
  let linked = List.filter (fun p -> List.exists (fun (m, _) -> List.mem_assoc m crcs) (Layouts.cmis p)) all in
  let libs =
    match Env.output_of "dune" [ "describe"; "external-lib-deps"; "--root"; root ] with
    | None -> []
    | Some s ->
        (* ((name required)) entries: the library names *)
        String.split_on_char '(' s
        |> List.filter_map (fun e ->
               match Str_util.words (String.map (fun c -> if c = ')' || c = '\n' then ' ' else c) e) with
               | [ lib; ("required" | "optional") ] -> Some (List.hd (String.split_on_char '.' lib))
               | _ -> None)
        |> List.sort_uniq compare
        |> List.filter_map (fun top -> Layouts.owner (Printf.sprintf "lib/%s/META" top))
  in
  let seen = Hashtbl.create 64 in
  let rec add p =
    if not (Hashtbl.mem seen p) then (
      Hashtbl.add seen p ();
      List.iter add (Layouts.deps p))
  in
  List.iter add ("dune" :: linked @ libs);
  Hashtbl.fold (fun p () acc -> p :: acc) seen []
  |> List.filter (fun p -> not (host_only p))
  |> List.sort compare
  |> List.filter_map (fun p -> Option.map (fun v -> (p, v)) (Layouts.version p))

let ensure_packages pkgs =
  let have = image_packages () in
  match List.filter (fun (p, v) -> List.assoc_opt p have <> Some v) pkgs with
  | [] -> ()
  | missing ->
      let specs = List.map (fun (p, v) -> p ^ "." ^ v) missing in
      Env.log "--docker: installing in %s: %s" (image ()) (String.concat " " specs);
      let name = Printf.sprintf "ocaml-emcc-setup-%d" (Unix.getpid ()) in
      let code = docker ([ "run"; "--platform"; !platform; "--name"; name; image () ] @ linux32 () @ ("opam" :: "install" :: specs)) in
      if code = 0 && Env.output_of "docker" [ "commit"; name; image () ] = None then Env.fail "docker commit failed";
      ignore (Env.output_of "docker" [ "rm"; name ]);
      if code <> 0 then Env.fail "--docker: opam could not install %s in the container" (String.concat " " specs)

(* Build [exe] (dune path without extension) in the container; the bytecode
   built, in ROOT/_build.docker-ARCH. *)
let build ~root ~exe ~host_bc =
  if !Env.target <> "wasm32" then Env.fail "--docker builds 32-bit bytecode: wasm32 only";
  check_docker ();
  base_image ();
  ensure_packages (packages ~root (Bytecode.parse host_bc));
  let bdir = Filename.concat root ("_build.docker-" ^ arch ()) in
  let cclibs = Env.sysroot_file "meta/cclibs" in
  (try Unix.mkdir cclibs 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  (* without ".." (_build/default/bin/../../../share): the path is mounted
     as is *)
  let share =
    let cwd = Sys.getcwd () in
    Sys.chdir (Env.share ());
    let d = Sys.getcwd () in
    Sys.chdir cwd;
    d
  in
  Env.log "--docker: building %s with the 32-bit OCaml of %s" exe (image ());
  let out = Filename.temp_file "ocaml-emcc" ".target" in
  let fd = Unix.openfile out [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let args =
    [ "docker"; "run"; "--rm"; "--platform"; !platform;
      "--user"; Printf.sprintf "%d:%d" (Unix.getuid ()) (Unix.getgid ()); "-e"; "HOME=/tmp";
      "-v"; root ^ ":" ^ root; "-v"; share ^ ":" ^ share ^ ":ro"; "-v"; cclibs ^ ":" ^ cclibs;
      "-w"; root; image () ]
    @ linux32 ()
    @ [ "sh"; Filename.concat share "tools/docker-build"; root; bdir; Env.sysroot ();
        "./" ^ exe ^ ".bc"; "./" ^ exe ^ ".exe" ]
  in
  if !Env.verbose then Env.log "%s" (Compat.quote_command "docker" (List.tl args));
  let pid = Unix.create_process "docker" (Array.of_list args) Unix.stdin fd Unix.stderr in
  Unix.close fd;
  let code = match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255 in
  let target = String.trim (Compat.read_file out) in
  Sys.remove out;
  if code <> 0 || target = "" then Env.fail "--docker: dune could not build %s in the container" exe;
  Filename.concat bdir (Filename.concat "default" target)
