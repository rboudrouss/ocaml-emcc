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
