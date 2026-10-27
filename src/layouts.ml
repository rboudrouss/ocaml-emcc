(* The C layouts computed when OCaml libraries were built.

   ctypes lays C types out (struct fields, sizeof, arrays) with the sizes it
   generated when it was built (ctypes_primitives.ml), and bindings that
   generate their type descriptions (yaml, posix-stat) print the offsets of
   the structs from a C program: those of the 64-bit host.  wasm32 has other
   sizes (long, size_t, pointers), and both targets another libc than the
   host (musl's struct stat is not glibc's).  So the packages of the program
   depending on ctypes are rebuilt for the target (driver.sh shadow) into
   the sysroot's findlib directory, which the toolchain searches before the
   switch, and the bytecode is built against them. *)

let opam_file rel = Filename.concat (Lazy.force Env.switch_prefix) (Filename.concat ".opam-switch" rel)

let read_opt f = if Sys.file_exists f then Some (Compat.read_file f) else None

(* installed opam packages: name -> version *)
let installed =
  lazy
    (let tbl = Hashtbl.create 256 in
     (try Sys.readdir (opam_file "packages") with Sys_error _ -> [||])
     |> Array.iter (fun e ->
            match String.index_opt e '.' with
            | Some i -> Hashtbl.replace tbl (String.sub e 0 i) (String.sub e (i + 1) (String.length e - i - 1))
            | None -> ());
     tbl)

let version pkg = Hashtbl.find_opt (Lazy.force installed) pkg

(* The `name: [...]` field of an opam file (lists of packages hold no ']') *)
let opam_field s name =
  let key = name ^ ": [" in
  let start =
    if Str_util.starts_with ~prefix:key s then Some 0
    else Option.map (fun i -> i + 1) (Str_util.find s ("\n" ^ key))
  in
  match start with
  | None -> ""
  | Some i -> (
      let i = i + String.length key in
      match String.index_from_opt s i ']' with Some j -> String.sub s i (j - i) | None -> "")

(* The "name" {filter} entries of a list of packages (formulas: their
   operators are skipped) *)
let entries s =
  let n = String.length s in
  let rec go acc i =
    match String.index_from_opt s i '"' with
    | None -> List.rev acc
    | Some a -> (
        match String.index_from_opt s (a + 1) '"' with
        | None -> List.rev acc
        | Some b ->
            let name = String.sub s (a + 1) (b - a - 1) in
            let j = ref (b + 1) in
            while !j < n && (s.[!j] = ' ' || s.[!j] = '\n') do incr j done;
            if !j < n && s.[!j] = '{' then
              let e = Option.value (String.index_from_opt s !j '}') ~default:(n - 1) in
              go ((name, String.sub s !j (e - !j + 1)) :: acc) (e + 1)
            else go ((name, "") :: acc) (b + 1))
  in
  go [] 0

(* The installed packages of the depends and depopts of [pkg] (optional
   dependencies matter once installed), not those for tests, documentation
   or development. *)
let deps pkg =
  match version pkg with
  | None -> []
  | Some v -> (
      match read_opt (opam_file (Printf.sprintf "packages/%s.%s/opam" pkg v)) with
      | None -> []
      | Some s ->
          let dev f = List.exists (fun w -> Str_util.find f w <> None) [ "with-test"; "with-doc"; "with-dev-setup" ] in
          entries (opam_field s "depends" ^ " " ^ opam_field s "depopts")
          |> List.filter_map (fun (d, f) ->
                 if d <> pkg && Hashtbl.mem (Lazy.force installed) d && not (dev f) then Some d else None)
          |> List.sort_uniq compare)

(* ctypes and the packages depending on it, directly or not *)
let ctypes_users =
  lazy
    (let users = Hashtbl.create 16 in
     if version "ctypes" <> None then Hashtbl.replace users "ctypes" ();
     let pkgs = Hashtbl.fold (fun p _ acc -> p :: acc) (Lazy.force installed) [] |> List.sort compare in
     let deps = List.map (fun p -> (p, deps p)) pkgs in
     let rec fix () =
       let added =
         List.filter
           (fun (p, ds) -> (not (Hashtbl.mem users p)) && List.exists (Hashtbl.mem users) ds)
           deps
       in
       List.iter (fun (p, _) -> Hashtbl.replace users p ()) added;
       if added <> [] then fix ()
     in
     fix ();
     (users, deps))

(* The interfaces [pkg] installed: (module, path relative to the switch) *)
let cmis pkg =
  match read_opt (opam_file ("install/" ^ pkg ^ ".changes")) with
  | None -> []
  | Some s ->
      String.split_on_char '"' s
      |> List.filter (fun f -> Str_util.starts_with ~prefix:"lib/" f && Filename.check_suffix f ".cmi")
      |> List.map (fun f -> (String.capitalize_ascii (Filename.chop_suffix (Filename.basename f) ".cmi"), f))

(* The packages depending on ctypes (and ctypes) whose modules [bc] links,
   dependencies first. *)
let packages bc =
  let crcs = Bytecode.crcs bc in
  if not (List.mem_assoc "Ctypes" crcs) then []
  else
    let users, deps = Lazy.force ctypes_users in
    let linked p = List.exists (fun (m, _) -> List.mem_assoc m crcs) (cmis p) in
    let seen = Hashtbl.create 16 and order = ref [] in
    let rec visit p =
      if not (Hashtbl.mem seen p) then (
        Hashtbl.add seen p ();
        List.iter (fun d -> if Hashtbl.mem users d then visit d) (Option.value (List.assoc_opt p deps) ~default:[]);
        if linked p then order := p :: !order)
    in
    List.iter (fun (p, _) -> if Hashtbl.mem users p then visit p) deps;
    List.rev !order

(* "deps=<pkg>.<version>,...": the users of ctypes [pkg] depends on, with
   their installed versions *)
let dep_versions pkg =
  let users, deps = Lazy.force ctypes_users in
  Option.value (List.assoc_opt pkg deps) ~default:[]
  |> List.filter (Hashtbl.mem users)
  |> List.map (fun d -> d ^ "." ^ Option.value (version d) ~default:"")
  |> String.concat ","
  |> ( ^ ) "deps="

(* "<version> <ok|failed|none> ... [deps=...]" (driver.sh run_shadow, then
   [record_deps]): the build of the installed version, against the
   installed versions of its dependencies *)
let stamp pkg =
  match read_opt (Env.sysroot_file ("stamps/shadow-" ^ pkg)) with
  | Some s -> (
      match Str_util.words (String.trim s) with
      | v :: status :: rest
        when Some v = version pkg
             && (List.mem (dep_versions pkg) rest || dep_versions pkg = "deps=") ->
          Some status
      | _ -> None)
  | None -> None

let record_deps pkg =
  let f = Env.sysroot_file ("stamps/shadow-" ^ pkg) in
  match read_opt f with
  | Some s ->
      let oc = open_out f in
      output_string oc (String.trim s ^ " " ^ dep_versions pkg ^ "\n");
      close_out oc
  | None -> ()

(* The builds for the target of packages since upgraded, downgraded or
   removed, or built against other versions of their dependencies: the
   toolchain would find them before the switch's (ctypes 0.24's next to
   ctypes-foreign 0.22: "inconsistent assumptions"). *)
(* Remove the build of [pkg] for the target: its libraries and stamp. *)
let drop pkg =
  let dirs = Env.sysroot_file ("meta/shadow-" ^ pkg ^ ".dirs") in
  let l = match read_opt dirs with Some s -> Str_util.words (String.map (fun c -> if c = '\n' then ' ' else c) s) | None -> [] in
  ignore (Env.run "rm" ("-rf" :: dirs :: Env.sysroot_file ("stamps/shadow-" ^ pkg)
                        :: List.map (fun d -> Env.sysroot_file ("lib/findlib/" ^ d)) l))

let prune () =
  let stamps = Env.sysroot_file "stamps" in
  (try Array.to_list (Sys.readdir stamps) with Sys_error _ -> [])
  |> List.iter (fun f ->
         if Str_util.starts_with ~prefix:"shadow-" f then
           let pkg = String.sub f 7 (String.length f - 7) in
           if stamp pkg = None then drop pkg)

(* [roots] and the users of ctypes they depend on, dependencies first *)
let with_deps roots =
  let users, deps = Lazy.force ctypes_users in
  let seen = Hashtbl.create 16 and order = ref [] in
  let rec visit p =
    if not (Hashtbl.mem seen p) then (
      Hashtbl.add seen p ();
      List.iter (fun d -> if Hashtbl.mem users d then visit d) (Option.value (List.assoc_opt p deps) ~default:[]);
      order := p :: !order)
  in
  List.iter visit roots;
  List.rev !order

(* whether [p] depends on [q], directly or not (or is [q]) *)
let depends_on p q =
  let _, deps = Lazy.force ctypes_users in
  let seen = Hashtbl.create 16 in
  let rec go p =
    p = q
    || (not (Hashtbl.mem seen p))
       && (Hashtbl.add seen p ();
           List.exists go (Option.value (List.assoc_opt p deps) ~default:[]))
  in
  go p

(* Those of [pkgs] (dependencies first) to build for the target: those
   without a build for this version, and those depending on one of them,
   whose build was compiled against the previous one (zstd 0.3 takes
   ctypes 0.20 along). *)
let to_build pkgs =
  List.fold_left
    (fun acc p -> if stamp p = None || List.exists (depends_on p) acc then acc @ [ p ] else acc)
    [] pkgs

(* Build [l] (dependencies first) for the target, one by one.  A package
   depending on one that could not be built keeps the host's build, as
   that one does (ctypes before 0.21, built by make): the bytecode is then
   compiled against consistent libraries, and `link` warns. *)
let shadow l =
  Env.log "ctypes: building %s for %s (C layouts)" (String.concat ", " l) !Env.target;
  let failed = ref [] in
  List.iter
    (fun p ->
      match List.find_opt (depends_on p) !failed with
      | Some q ->
          Env.log "  %s: not built for %s, as %s could not be" p !Env.target q;
          drop p;
          (match version p with
          | Some v ->
              let oc = open_out (Env.sysroot_file ("stamps/shadow-" ^ p)) in
              output_string oc (v ^ " failed " ^ dep_versions p ^ "\n");
              close_out oc
          | None -> ());
          failed := p :: !failed
      | None ->
          let ok = Env.driver [ "shadow"; "--force"; p ] = 0 in
          record_deps p;
          if (not ok) || stamp p = Some "failed" then failed := p :: !failed)
    l;
  if !failed <> [] then
    Env.log "warning: could not build the %s libraries of %s" !Env.target (String.concat ", " (List.rev !failed));
  !failed = []

(* Build the missing libraries of the packages of [bc] for the target;
   whether there were any. *)
let ensure bc =
  match to_build (packages bc) with
  | [] -> false
  | l -> ignore (shadow l); true

(* The opam package that installed [rel] (relative to the switch) *)
let owner rel =
  let dir = opam_file "install" in
  let needle = "\"" ^ rel ^ "\"" in
  (try Array.to_list (Sys.readdir dir) with Sys_error _ -> [])
  |> List.sort compare
  |> Compat.find_map (fun f ->
         if not (Filename.check_suffix f ".changes") then None
         else if Str_util.find (Compat.read_file (Filename.concat dir f)) needle <> None then
           Some (Filename.chop_suffix f ".changes")
         else None)

(* ocamlc's "Files A and B make inconsistent assumptions over interface X"
   (A and B quoted since 5.2): a library of the switch compiled against the
   host's build of a package rebuilt for the target (ctypes-foreign imports
   Ctypes_primitives).  Its package is rebuilt as well; whether there was
   one to rebuild. *)
let fix_inconsistent err =
  if Str_util.find err "inconsistent assumptions" = None then false
  else
    let lib = Filename.concat (Lazy.force Env.switch_prefix) "lib/" in
    let prefix = Lazy.force Env.switch_prefix ^ "/" in
    let words =
      String.split_on_char ' ' (String.map (fun c -> if String.contains "\n\t()\"" c then ' ' else c) err)
    in
    let pkgs =
      List.filter_map
        (fun w ->
          if Str_util.starts_with ~prefix:lib w then
            owner (String.sub w (String.length prefix) (String.length w - String.length prefix))
          else None)
        words
      |> List.sort_uniq compare
      |> List.filter (fun p -> stamp p = None)
    in
    if pkgs = [] then false
    else (
      Env.log "%s: compiled against the host's build of a library rebuilt for %s, rebuilding it too"
        (String.concat ", " pkgs) !Env.target;
      shadow (to_build (with_deps pkgs)))

type state =
  | Rebuilt  (** the bytecode uses its build for the target *)
  | Stale  (** it has one, the bytecode was built against the host's *)
  | Not_rebuilt  (** it lays C types out when built, and has none *)
  | Unneeded  (** it does not lay C types out *)

(* (unit, CRC) of interfaces, from ocamlobjinfo *)
let cmi_crcs files =
  if files = [] then []
  else
    match Env.output_of (Filename.concat (Env.host_bin ()) "ocamlobjinfo") files with
    | None -> []
    | Some out ->
        let unit = ref "" in
        String.split_on_char '\n' out
        |> List.filter_map (fun l ->
               let u = "Unit name: " in
               if Str_util.starts_with ~prefix:u l then (
                 unit := String.trim (String.sub l (String.length u) (String.length l - String.length u));
                 None)
               else
                 match String.split_on_char '\t' l with
                 | [ ""; crc; name ] when name = !unit -> Some (name, crc)
                 | _ -> None)

let state crcs pkg =
  match stamp pkg with
  | Some "ok" ->
      (* the interfaces built for the target, at the same place under lib/findlib *)
      let files =
        List.filter_map
          (fun (m, f) ->
            let f = Env.sysroot_file ("lib/findlib/" ^ String.sub f 4 (String.length f - 4)) in
            if List.mem_assoc m crcs && Sys.file_exists f then Some f else None)
          (cmis pkg)
      in
      (* Only the interfaces are known: a bytecode is caught by those that
         differ (ctypes_primitives.cmi, which every user of ctypes links). *)
      if List.for_all (fun (m, crc) -> List.assoc_opt m crcs = Some crc) (cmi_crcs files) then Rebuilt else Stale
  | Some "none" -> Unneeded
  | _ -> Not_rebuilt

let states bc =
  let crcs = Bytecode.crcs bc in
  List.map (fun p -> (p, state crcs p)) (packages bc)

let with_state st l = List.filter_map (fun (p, s) -> if s = st then Some p else None) l

let wrong () =
  if !Env.target = "wasm32" then "struct fields, sizeof, arrays of long, size_t or pointers are those of the 64-bit host"
  else "the fields of the libc's structs are those of the host's libc"

let warn ~bc_path bc =
  let l = states bc in
  (match with_state Stale l with
  | [] -> ()
  | ps ->
      Env.log
        "warning: %s was built against the host's %s, whose C layouts (%s) are wrong on %s.\n\
        \  Their %s builds are in %s: build the bytecode with them\n\
        \  (ocaml-emcc build or ocaml-emcc dune, or ocamlfind -toolchain %s with\n\
        \  OCAMLFIND_CONF=%s)."
        bc_path (String.concat ", " ps) (wrong ()) !Env.target !Env.target (Env.sysroot_file "lib/findlib")
        !Env.target (Env.sysroot_file "findlib.conf"));
  match with_state Not_rebuilt l with
  | [] -> ()
  | ps ->
      Env.log
        "warning: %s could not be built for %s: the C layouts of their ctypes bindings\n\
        \  (%s) are wrong there."
        (String.concat ", " ps) !Env.target (wrong ())
