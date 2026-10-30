(* The system C libraries an opam package uses, for which a recipe exists
   (SOURCE=system: recipes, see driver.sh). *)

(* The "conf-X" packages an opam file mentions, sorted *)
let conf_packages opam =
  let n = String.length opam in
  let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_' || c = '-' in
  let rec go acc i =
    match Str_util.find (String.sub opam i (n - i)) "\"conf-" with
    | None -> acc
    | Some k ->
        let a = i + k + 1 in
        let j = ref (a + 5) in
        while !j < n && ok opam.[!j] do incr j done;
        let acc = if !j < n && opam.[!j] = '"' && !j > a + 5 then String.sub opam a (!j - a) :: acc else acc in
        go acc !j
  in
  List.sort_uniq compare (go [] 0)

(* The X of the -lX in ocamlobjinfo's output for a .cma (ocamlmklib -l,
   -cclib), from the header before the units *)
let objinfo_libs out =
  let rec go acc = function
    | [] -> acc
    | l :: _ when Str_util.starts_with ~prefix:"Unit name" l -> acc
    | l :: rest ->
        let field =
          Compat.find_map
            (fun prefix ->
              if Str_util.starts_with ~prefix l then Some (String.sub l (String.length prefix) (String.length l - String.length prefix))
              else None)
            [ "Extra C object files:"; "Extra C options:" ]
        in
        let words = match field with Some f -> Str_util.words f | None -> [] in
        go (List.rev_append words acc) rest
  in
  go [] (String.split_on_char '\n' out)
  |> List.filter_map (fun w ->
         if Str_util.starts_with ~prefix:"-l" w && String.length w > 2 then Some (String.sub w 2 (String.length w - 2)) else None)
  |> List.sort_uniq compare

(* The X of the -lX recorded in the .cma files [pkg] installed, its own
   stubs included *)
let cma_libs pkg =
  let objinfo = Filename.concat (Env.host_bin ()) "ocamlobjinfo" in
  Switch.lib_files pkg
  |> List.filter (fun f -> Filename.check_suffix f ".cma")
  |> Compat.concat_map (fun f ->
         objinfo_libs (Option.value (Env.output_of objinfo [ Filename.concat (Switch.prefix ()) f ]) ~default:""))
  |> List.sort_uniq compare

(* The system libraries [pkg] uses for which a recipe exists: its installed
   conf-X dependencies (recipe X), and the -lX its OCaml libraries ask for
   (glpk, which has no conf-glpk; see Recipe.lib_recipe). *)
let recipes ?(path = Env.recipes_path ()) pkg =
  match Switch.opam pkg with
  | None -> []
  | Some opam ->
      let confs =
        conf_packages opam
        |> List.filter_map (fun c ->
               let r = String.sub c 5 (String.length c - 5) in
               if Switch.is_installed c && Recipe.find ~path r <> None then Some r else None)
      in
      let libs = List.filter_map (Recipe.lib_recipe ~path) (cma_libs pkg) in
      List.fold_left (fun acc r -> if List.mem r acc then acc else acc @ [ r ]) [] (confs @ libs)
