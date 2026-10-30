(* Mapping the stub DLLs named in a bytecode executable (DLLS section) to
   static wasm archives, and obtaining the missing ones. *)

let lib_file dir name = Filename.concat dir ("lib" ^ name ^ ".a")

(* The bytecode records where the stub DLLs were found (DLPT).  For a dune
   project, `_build/default/x` has a wasm twin `_build/default.wasm64/x`
   built by `ocaml-emcc build` (dune -x wasm64).  A bytecode built in the
   wasm context itself already points there. *)
let wasm_twin dir =
  let marker = "/_build/default/" in
  let dir = if Filename.check_suffix dir "/" then dir else dir ^ "/" in
  match Str_util.find dir marker with
  | Some i ->
      let pre = String.sub dir 0 i in
      let post = String.sub dir (i + String.length marker) (String.length dir - i - String.length marker) in
      Some (pre ^ "/_build/default." ^ !Env.target ^ "/" ^ post)
  | None -> None

(* dune does not record -dllpath for the project's own libraries: look for
   archives anywhere in the wasm context of the enclosing dune build dir. *)
let rec build_root dir =
  if Filename.basename dir = "_build" then Some dir
  else
    let parent = Filename.dirname dir in
    if parent = dir then None else build_root parent

let archive_dirs root =
  let acc = ref [] in
  let rec walk d =
    match Sys.readdir d with
    | exception Sys_error _ -> ()
    | entries ->
        if Array.exists (fun e -> Filename.check_suffix e ".a" && Str_util.starts_with ~prefix:"lib" e) entries then
          acc := d :: !acc;
        Array.iter
          (fun e ->
            let p = Filename.concat d e in
            if e.[0] <> '.' && Sys.is_directory p then walk p)
          entries
  in
  walk root;
  List.rev !acc

let absolute p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p

let context_dirs bc_path =
  let roots =
    List.filter_map build_root [ Filename.dirname (absolute bc_path) ]
    @ [ Filename.concat (Sys.getcwd ()) "_build" ]
  in
  List.sort_uniq compare roots
  |> Compat.concat_map (fun r -> archive_dirs (Filename.concat r ("default." ^ !Env.target)))

let search_dirs ~extra_dirs ?(bc_path = "") bc =
  let dlpt = Bytecode.dll_paths bc in
  extra_dirs
  @ List.filter_map wasm_twin dlpt
  @ List.filter (fun d -> Str_util.find d ("/_build/default." ^ !Env.target) <> None) dlpt
  @ (if bc_path = "" then [] else context_dirs bc_path)
  @ [ Env.sysroot_file "lib" ]

let find_lib dirs name =
  Compat.find_map (fun d -> let f = lib_file d name in if Sys.file_exists f then Some f else None) dirs

(* opam package that installed lib/stublibs/dll<name>.so *)
let owner_of_dll name = Switch.owner (Printf.sprintf "lib/stublibs/dll%s.so" name)

(* Libraries built by the `ocaml` recipe. *)
let compiler_libs = [ "camlrun"; "unix"; "camlstr"; "camlruntime_events"; "unixbyt"; "camlstrbyt"; "camlruntime_eventsbyt"; "threads"; "threadsbyt" ]

type status = Found of string | Local of string | Missing of string option (* owner *)

let resolve ~extra_dirs ?bc_path bc name =
  match find_lib (search_dirs ~extra_dirs ?bc_path bc) name with
  | Some f -> Found f
  | None ->
      if List.mem name compiler_libs then Missing (Some "ocaml")
      else (
        match owner_of_dll name with
        | Some pkg -> Missing (Some pkg)
        | None ->
            (* Not installed through opam: most likely the project's own stubs. *)
            Local name)

(* The opam package of a stub library of the sysroot built from it (by
   dune or blindly: meta/<name>.provider, and a stamp starting with the
   version; by a recipe: its stamp ends with opam=<package>) for another
   version than the installed one (opam upgrade). *)
let stale name f =
  let read rel = let p = Env.sysroot_file rel in if Sys.file_exists p then Some (String.trim (Bytecode.read_file p)) else None in
  let older pkg stamp =
    match Stamp.read stamp, Switch.version pkg with
    | Some fields, Some installed when Stamp.version fields <> installed -> Some pkg
    | _ -> None
  in
  if f <> lib_file (Env.sysroot_file "lib") name then None
  else
    match owner_of_dll name, read ("meta/" ^ name ^ ".provider") with
    | Some pkg, Some p when p = "dune-" ^ pkg || p = "auto-" ^ pkg ->
        older pkg (if p = "dune-" ^ pkg then p else p ^ "-" ^ name)
    | Some pkg, Some recipe -> (
        match Stamp.read recipe with
        | Some fields when Stamp.field "opam" fields = Some pkg -> older pkg recipe
        | _ -> None)
    | _ -> None

(* Build what can be built: a recipe named after the package, the package's
   dune rules (dune -x <target>), or a blind compilation of its stubs.  A
   library of the compiler missing from a built runtime (libthreads.a, built
   since): the runtime is built again. *)
let obtain pkg name =
  if pkg = "ocaml" then Recipe.install ~force:(Stamp.read "ocaml" <> None) "ocaml"
  else
    try Stubs.obtain pkg name with Env.Failed -> Env.fail "could not build lib%s.a (package %s)" name pkg

(* The recipe of the C library lib<name>.a (-lgmp, -lz...), if any. *)
let lib_recipe name = Recipe.lib_recipe name

let install_recipe r = Recipe.install r

(* Extra link flags recorded by recipes (e.g. zarith -> -lgmp). *)
let link_flags name =
  let f = Env.sysroot_file (Printf.sprintf "meta/%s.link" name) in
  if Sys.file_exists f then
    String.split_on_char ' ' (String.trim (Bytecode.read_file f)) |> List.filter (( <> ) "")
  else []
