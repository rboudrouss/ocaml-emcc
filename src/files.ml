(* Looking for files in source trees. *)

(* The files under [dir] (paths starting with [dir]) satisfying [pred] on
   their name, in name order, not looking into the directories [skip]
   rejects (by name) *)
let find ?(skip = fun _ -> false) dir pred =
  let rec walk d =
    (try List.sort compare (Array.to_list (Sys.readdir d)) with Sys_error _ -> [])
    |> Compat.concat_map (fun e ->
           let p = Filename.concat d e in
           match (Unix.lstat p).Unix.st_kind with
           | Unix.S_DIR -> if skip e then [] else walk p
           | _ -> if pred e then [ p ] else []
           | exception Unix.Unix_error _ -> [])
  in
  walk dir

let first ?skip dir pred = match find ?skip dir pred with f :: _ -> Some f | [] -> None

let hidden name = name <> "" && name.[0] = '.'

let is_dir d = Sys.file_exists d && Sys.is_directory d

let contents f = try Compat.read_file f with Sys_error _ -> ""

(* Whether [s] has [word] with no identifier character around it (grep -w) *)
let has_word s word =
  let n = String.length s and m = String.length word in
  let ident c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' in
  let rec go i =
    match Str_util.find_from s i word with
    | None -> false
    | Some a ->
        ((a = 0 || not (ident s.[a - 1])) && (a + m = n || not (ident s.[a + m]))) || go (a + 1)
  in
  go 0

(* Whether [s] has [a], then spaces (if [space]: at least one, tabs too),
   then one of [bs] *)
let has_seq ?(space = false) s a bs =
  let n = String.length s and la = String.length a in
  let rec go i =
    match Str_util.find_from s i a with
    | None -> false
    | Some k ->
        let j = ref (k + la) in
        while !j < n && (s.[!j] = ' ' || (space && s.[!j] = '\t')) do incr j done;
        (((not space) || !j > k + la)
        && List.exists (fun b -> !j + String.length b <= n && String.sub s !j (String.length b) = b) bs)
        || go (k + 1)
  in
  go 0
