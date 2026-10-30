(* What the opam switch providing the host compiler has installed, read
   from its .opam-switch directory. *)

let prefix () = Lazy.force Env.switch_prefix

let opam_file rel = Filename.concat (prefix ()) (Filename.concat ".opam-switch" rel)

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

let is_installed pkg = Hashtbl.mem (Lazy.force installed) pkg

(* The opam file of the installed version of [pkg] *)
let opam pkg =
  match version pkg with
  | None -> None
  | Some v -> read_opt (opam_file (Printf.sprintf "packages/%s.%s/opam" pkg v))

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

(* The files [pkg] installed in lib/, relative to the switch *)
let lib_files pkg =
  match read_opt (opam_file ("install/" ^ pkg ^ ".changes")) with
  | None -> []
  | Some s -> String.split_on_char '"' s |> List.filter (fun f -> Str_util.starts_with ~prefix:"lib/" f)
