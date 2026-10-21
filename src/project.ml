(* Per-project configuration: `ocaml-emcc.conf`, looked up from the current
   directory upwards.

     # comments
     target: wasm32                  default target of the project
     recipes: emcc-recipes vendor/r  recipe directories (relative to the file)
     requires: cjson                 recipes built before build/link
     link-flags: -lcjson -sMODULARIZE=1
     cflags: -DFOO                   extra C flags (stubs and recipes)

   Without a configuration file, `emcc-recipes/` next to the nearest
   dune-project is still picked up as a recipe directory. *)

type t = {
  dir : string option;  (** directory holding the conf / dune-project *)
  target : string option;
  recipes : string list;  (** absolute paths *)
  requires : string list;
  link_flags : string list;
  cflags : string list;
}

let empty = { dir = None; target = None; recipes = []; requires = []; link_flags = []; cflags = [] }

let rec find_up dir names =
  match List.find_opt (fun n -> Sys.file_exists (Filename.concat dir n)) names with
  | Some n -> Some (dir, n)
  | None ->
      let parent = Filename.dirname dir in
      if parent = dir then None else find_up parent names

let parse_file file =
  Compat.read_file file
  |> String.split_on_char '\n'
  |> List.filter_map (fun line ->
         let line = match String.index_opt line '#' with Some i -> String.sub line 0 i | None -> line in
         let sep = match (String.index_opt line ':', String.index_opt line '=') with
           | Some i, Some j -> Some (min i j) | Some i, None | None, Some i -> Some i | None, None -> None
         in
         match sep with
         | None -> None
         | Some i ->
             let key = String.trim (String.sub line 0 i) in
             let v = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
             if key = "" then None else Some (key, v))

let load () =
  let cwd = Sys.getcwd () in
  let absolute dir p = if Filename.is_relative p then Filename.concat dir p else p in
  let default_recipes dir =
    let d = Filename.concat dir "emcc-recipes" in
    if Sys.file_exists d && Sys.is_directory d then [ d ] else []
  in
  match find_up cwd [ "ocaml-emcc.conf" ] with
  | Some (dir, name) ->
      let kv = parse_file (Filename.concat dir name) in
      let get k = List.filter_map (fun (k', v) -> if k = k' then Some v else None) kv in
      let words k = Compat.concat_map Str_util.words (get k) in
      let recipes = List.map (absolute dir) (words "recipes") in
      {
        dir = Some dir;
        target = (match get "target" with [] -> None | l -> Some (List.nth l (List.length l - 1)));
        recipes = (if recipes = [] then default_recipes dir else recipes);
        requires = words "requires";
        link_flags = words "link-flags";
        cflags = words "cflags";
      }
  | None -> (
      match find_up cwd [ "dune-project" ] with
      | Some (dir, _) -> { empty with dir = Some dir; recipes = default_recipes dir }
      | None -> empty)

let current = lazy (load ())
let get () = Lazy.force current
