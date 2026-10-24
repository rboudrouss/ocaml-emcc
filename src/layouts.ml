(* wasm32: the C layouts computed when OCaml libraries were built.

   ctypes lays C types out (struct fields, sizeof, arrays) with the sizes it
   generated when it was built (ctypes_primitives.ml), and bindings that
   generate their type descriptions (yaml) print the offsets of the structs
   from a C program: those of the 64-bit host, which wasm64 shares but not
   wasm32.  On wasm32, the packages of the program depending on ctypes are
   rebuilt for the target (driver.sh shadow) into the sysroot's findlib
   directory, which the toolchain searches before the switch, and the
   bytecode is built against them. *)

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

(* "<version> <ok|failed|none> ..." (driver.sh run_shadow) *)
let stamp pkg =
  match read_opt (Env.sysroot_file ("stamps/shadow-" ^ pkg)) with
  | Some s -> (
      match Str_util.words (String.trim s) with
      | v :: status :: _ when Some v = version pkg -> Some status
      | _ -> None)
  | None -> None

(* Build the missing wasm32 libraries of the packages of [bc]; whether
   there were any. *)
let ensure bc =
  match List.filter (fun p -> stamp p = None) (packages bc) with
  | [] -> false
  | l ->
      Env.log "ctypes on wasm32: building %s for wasm32 (C layouts)" (String.concat ", " l);
      if Env.driver ("shadow" :: l) <> 0 then Env.log "warning: could not build the wasm32 libraries of %s" (String.concat ", " l);
      true

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

(* ocamlc's "Files A and B make inconsistent assumptions over interface X":
   a library of the switch compiled against the host's build of a package
   rebuilt for wasm32 (ctypes-foreign imports Ctypes_primitives).  Its
   package is rebuilt as well; whether there was one to rebuild. *)
let fix_inconsistent err =
  if Str_util.find err "inconsistent assumptions" = None then false
  else
    let lib = Filename.concat (Lazy.force Env.switch_prefix) "lib/" in
    let prefix = Lazy.force Env.switch_prefix ^ "/" in
    let words =
      String.split_on_char ' ' (String.map (fun c -> if String.contains "\n\t()" c then ' ' else c) err)
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
      Env.log "%s: compiled against the host's build of a library rebuilt for wasm32, rebuilding it too"
        (String.concat ", " pkgs);
      Env.driver ("shadow" :: pkgs) = 0)

type state =
  | Rebuilt  (** the bytecode uses its wasm32 build *)
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
      (* the wasm32 interfaces, at the same place under lib/findlib *)
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

let wrong = "struct fields, sizeof, arrays of long, size_t or pointers are those of the 64-bit host"

let warn ~bc_path bc =
  let l = states bc in
  (match with_state Stale l with
  | [] -> ()
  | ps ->
      Env.log
        "warning: %s was built against the host's %s, whose C layouts (%s) are wrong on wasm32.\n\
        \  Their wasm32 builds are in %s: build the bytecode with them\n\
        \  (ocaml-emcc build or ocaml-emcc dune, or ocamlfind -toolchain wasm32 with\n\
        \  OCAMLFIND_CONF=%s), or use --target wasm64."
        bc_path (String.concat ", " ps) wrong (Env.sysroot_file "lib/findlib") (Env.sysroot_file "findlib.conf"));
  match with_state Not_rebuilt l with
  | [] -> ()
  | ps ->
      Env.log
        "warning: %s could not be built for wasm32: the C layouts of their ctypes bindings\n\
        \  (%s) are wrong on wasm32.  Use --target wasm64."
        (String.concat ", " ps) wrong
