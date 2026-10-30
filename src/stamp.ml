(* Stamps: $SYSROOT/stamps/<name>, one line of space-separated fields
   recording what was built, whose first field is the version of the
   sources (possibly empty).

     <recipe>              <version> emcc-<v> recipe=<checksum> [opam=<package>]
     dune-<package>        <version> emcc-<v>
     auto-<package>-<lib>  <version> emcc-<v>
     shadow-<package>      <version> <ok|failed|none> emcc-<v> [deps=<p>.<v>,...]
     patched-dune          <version> patch=<checksum> *)

let file name = Env.sysroot_file (Filename.concat "stamps" name)

(* The fields of a line ("" before a leading space: no version) *)
let parse line =
  let line = match String.index_opt line '\n' with Some i -> String.sub line 0 i | None -> line in
  match String.split_on_char ' ' line with
  | v :: rest -> v :: List.filter (( <> ) "") rest
  | [] -> [ "" ]

let read name = let f = file name in if Sys.file_exists f then Some (parse (Compat.read_file f)) else None

let write name fields =
  let f = file name in
  if not (Sys.file_exists (Filename.dirname f)) then Unix.mkdir (Filename.dirname f) 0o755;
  Compat.write_file f (String.concat " " fields ^ "\n")

let remove name = try Sys.remove (file name) with Sys_error _ -> ()

let version = function v :: _ -> v | [] -> ""

(* The value of a key=value field *)
let field key fields =
  let prefix = key ^ "=" in
  Compat.find_map
    (fun f ->
      if Str_util.starts_with ~prefix f then Some (String.sub f (String.length prefix) (String.length f - String.length prefix))
      else None)
    fields

(* The names of the stamps of the sysroot *)
let names () = try List.sort compare (Array.to_list (Sys.readdir (Env.sysroot_file "stamps"))) with Sys_error _ -> []
