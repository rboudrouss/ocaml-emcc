(* Recipes: directories <name>/ holding a recipe.sh (see driver.sh), looked
   up along the recipe path (Env.recipes_path). *)

let script dir = Filename.concat dir "recipe.sh"

(* The directory of the recipe [name], the first one along [path] *)
let find ?(path = Env.recipes_path ()) name =
  List.map (fun d -> Filename.concat d name) path |> List.find_opt (fun d -> Sys.file_exists (script d))

(* The regular files under [dir], recursively, relative to it, in byte
   order (as `LC_ALL=C sort` orders them) *)
let files dir =
  let rec walk rel =
    let d = if rel = "" then dir else Filename.concat dir rel in
    (try Array.to_list (Sys.readdir d) with Sys_error _ -> [])
    |> Compat.concat_map (fun e ->
           let r = if rel = "" then e else Filename.concat rel e in
           match (Unix.lstat (Filename.concat dir r)).Unix.st_kind with
           | Unix.S_REG -> [ r ]
           | Unix.S_DIR -> walk r
           | _ -> []
           | exception Unix.Unix_error _ -> [])
  in
  List.sort compare (walk "")

(* Checksum of every recipe named [name] along the path (a recipe may
   include the next one): its recipe.sh, then its other files (patches...).
   The first 16 hex digits of a SHA-256, as recorded in the stamps. *)
let sum ?(path = Env.recipes_path ()) name =
  let b = Buffer.create 4096 in
  List.iter
    (fun d ->
      let dir = Filename.concat d name in
      if Sys.file_exists (script dir) then (
        Buffer.add_string b (Compat.read_file (script dir));
        List.iter
          (fun f -> if f <> "recipe.sh" then Buffer.add_string b (Compat.read_file (Filename.concat dir f)))
          (files dir)))
    path;
  let tmp = Filename.temp_file "ocaml-emcc" ".sum" in
  Compat.write_file tmp (Buffer.contents b);
  let out = Env.output_of "sha256sum" [ tmp ] in
  Sys.remove tmp;
  match out with
  | Some s when String.length s >= 16 -> String.sub s 0 16
  | _ -> Env.fail "sha256sum failed"

(* The value assigned to [var] on a line of [s] starting with VAR=, quotes
   stripped (up to the closing one): LIB_PATTERNS='clang* LLVM*' *)
let assignments s var =
  let prefix = var ^ "=" in
  String.split_on_char '\n' s
  |> List.filter_map (fun l ->
         if not (Str_util.starts_with ~prefix l) then None
         else
           let v = String.sub l (String.length prefix) (String.length l - String.length prefix) in
           let v = if v <> "" && (v.[0] = '"' || v.[0] = '\'') then String.sub v 1 (String.length v - 1) else v in
           let stop = Compat.find_map (fun c -> String.index_opt v c) [ '"'; '\'' ] in
           let v = match stop with Some i -> String.sub v 0 i | None -> v in
           Some v)

(* Shell glob matching, `*` and `?` only *)
let glob pat s =
  let n = String.length pat and m = String.length s in
  let rec go i j =
    if i = n then j = m
    else
      match pat.[i] with
      | '*' -> go (i + 1) j || (j < m && go i (j + 1))
      | '?' -> j < m && go (i + 1) (j + 1)
      | c -> j < m && s.[j] = c && go (i + 1) (j + 1)
  in
  go 0 0

(* The recipe of a C library (SOURCE=system:, or with a LINK or
   LIB_PATTERNS) that builds lib<x>.a (for a -l<x> of the program): named x
   or libx (whatever the case: sdl2 for -lSDL2), whose LINK starts with -lx
   (zlib: -lz), or with a LIB_PATTERNS glob matching x (clang: -lclang-cpp,
   -lLLVM-19). *)
let lib_recipe ?(path = Env.recipes_path ()) x =
  let lower = String.lowercase_ascii x in
  let matches name s =
    name = lower || name = "lib" ^ lower
    || List.exists (fun v -> List.nth_opt (Str_util.words v) 0 = Some ("-l" ^ x)) (assignments s "LINK")
    || List.exists (fun v -> List.exists (fun p -> glob p x) (Str_util.words v)) (assignments s "LIB_PATTERNS")
  in
  let is_lib s =
    List.exists
      (fun l -> List.exists (fun prefix -> Str_util.starts_with ~prefix l) [ "SOURCE=system:"; "LINK="; "LIB_PATTERNS=" ])
      (String.split_on_char '\n' s)
  in
  path
  |> Compat.find_map (fun d ->
         (try List.sort compare (Array.to_list (Sys.readdir d)) with Sys_error _ -> [])
         |> Compat.find_map (fun name ->
                let f = script (Filename.concat d name) in
                match Compat.read_file f with
                | s when is_lib s && matches name s -> Some name
                | _ -> None
                | exception Sys_error _ -> None))

(* ------------------------------------------------------------- install *)

(* The variables of the recipe [name] (driver.sh describe): SOURCE,
   DEPENDS, LINK... *)
let describe name =
  match Env.driver_output [ "describe"; name ] with
  | None -> Env.fail "could not read the %s recipe" name
  | Some out ->
      String.split_on_char '\000' out
      |> List.filter_map (fun kv ->
             match String.index_opt kv '=' with
             | Some i -> Some (String.sub kv 0 i, String.sub kv (i + 1) (String.length kv - i - 1))
             | None -> None)

let var vars v = Option.value (List.assoc_opt v vars) ~default:""

(* The opam package whose sources a recipe builds (SOURCE=opam:PKG) *)
let opam_package vars =
  let s = var vars "SOURCE" in
  if Str_util.starts_with ~prefix:"opam:" s then Some (String.sub s 5 (String.length s - 5)) else None

type decision = Built of string option  (** a note to show *) | Build of string option  (** why *)

(* Whether the recipe [name] is to be built, from its [stamp]: once built,
   it is not built again, unless [force]d, or it was built from the
   sources of an opam package (opam=PKG) since upgraded.  A recipe changed
   since ([sum]) is only noted: some take a while (clang).  [installed]: the
   version of an opam package in the switch ("" if none). *)
let decide ~force ~sum ~installed name stamp =
  match stamp with
  | Some fields when not force -> (
      match Stamp.field "opam" fields with
      | Some p when installed p <> Stamp.version fields ->
          Build (Some (Printf.sprintf "%s was built from %s %s, building it again for %s" name p (Stamp.version fields) (installed p)))
      | _ ->
          (* (stamps written before checksums were recorded have none) *)
          Built
            (match Stamp.field "recipe" fields with
            | Some s when s <> sum ->
                Some (Printf.sprintf "note: the %s recipe changed since it was built; rebuild with: ocaml-emcc install --force %s" name name)
            | _ -> None))
  | _ -> Build None

(* Copy the sources of the recipe [name] to [work]: their version, None
   for SOURCE=fetch (the recipe's own `fetch`, run by driver.sh build) *)
let fetch vars name work =
  let var = var vars in
  let s = var "SOURCE" in
  let kind, arg =
    match String.index_opt s ':' with
    | Some i -> (String.sub s 0 i, String.sub s (i + 1) (String.length s - i - 1))
    | None -> (s, "")
  in
  match kind with
  | "opam" -> Some (Source.opam_source arg work)
  | "url" -> Some (Source.url ~sha256:(var "SHA256") arg work)
  | "git" ->
      let repo, ref_ =
        match String.rindex_opt arg '#' with
        | Some i -> (String.sub arg 0 i, String.sub arg (i + 1) (String.length arg - i - 1))
        | None -> (arg, var "REF")
      in
      Some (Source.git repo ref_ work)
  | "dir" ->
      let d =
        if Filename.is_relative arg then Filename.concat (Option.get (find name)) arg else arg
      in
      Source.copy d work;
      Some (Filename.basename d)
  | "ocaml" -> Some (Source.ocaml work)
  | "system" ->
      let releases =
        if List.mem "releases" (Str_util.words (var "FUNCTIONS")) then
          match Env.driver_output [ "releases"; name ] with
          | Some out -> Some (List.filter (( <> ) "") (String.split_on_char '\n' out))
          | None -> Env.fail "%s: its releases function failed" name
        else None
      in
      Some (Source.system ~var ~releases arg work)
  | "fetch" -> None
  | "none" -> Source.sh "mkdir" [ "-p"; work ]; Some ""
  | _ -> Env.fail "%s: bad SOURCE '%s'" name s

(* Build and install the recipe [name] unless it is built, its DEPENDS
   first (not forced) *)
let rec install ?(force = false) name =
  let sum = sum name in
  let installed p = Option.value (Switch.version p) ~default:"" in
  match decide ~force ~sum ~installed name (Stamp.read name) with
  | Built note -> Option.iter (Env.log "%s") note
  | Build why ->
      Option.iter (Env.log "%s") why;
      if find name = None then Env.fail "no recipe named '%s'" name;
      let vars = describe name in
      List.iter (install ~force:false) (Str_util.words (var vars "DEPENDS"));
      let work = Env.sysroot_file (Filename.concat "build" name) in
      Source.remove work;
      Source.sh "mkdir" [ "-p"; Filename.dirname work ];
      let version = fetch vars name work in
      let result = Filename.temp_file "ocaml-emcc" ".result" in
      let code = Env.driver ([ "build"; name; result ] @ Option.to_list version) in
      let lines = String.split_on_char '\n' (Compat.read_file result) in
      Sys.remove result;
      if code <> 0 then Env.fail "the %s recipe failed" name;
      let source_version, emcc_version =
        match lines with v :: e :: _ -> (v, e) | _ -> Env.fail "the %s recipe did not complete" name
      in
      Stamp.write name
        ([ source_version; "emcc-" ^ emcc_version; "recipe=" ^ sum ]
        @ match opam_package vars with Some p -> [ "opam=" ^ p ] | None -> [])
