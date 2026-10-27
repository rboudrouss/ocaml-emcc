(* mccs, opam's dependency solver: C++ (with the copy of GLPK it bundles)
   behind stubs that convert CUDF universes to C++ and back *)
let pkg ?(depends = []) ?(conflicts = []) ?(installed = false) name version =
  (* a package conflicts with its other versions, as in opam's universes *)
  { Cudf.default_package with package = name; version; depends; installed;
                              conflicts = (name, None) :: conflicts }

let solve title criteria universe request =
  let u = Cudf.load_universe universe in
  let req = { Cudf.default_request with request_id = title; install = request } in
  match Mccs.resolve_cudf criteria (Cudf.default_preamble, u, req) with
  | None -> Printf.printf "%s: no solution\n" title
  | Some (_, sol) ->
    let l = Cudf.get_packages ~filter:(fun p -> p.Cudf.installed) sol in
    let l = List.sort compare (List.map (fun p -> Printf.sprintf "%s.%d" p.Cudf.package p.Cudf.version) l) in
    Printf.printf "%s: %s\n%!" title (String.concat " " l)

let () =
  let universe = [
    pkg "a" 1 ~installed:true; pkg "a" 2; pkg "a" 3;
    pkg "b" 1; pkg "b" 2 ~depends:[ [ ("a", Some (`Geq, 2)) ] ];
    pkg "c" 1 ~conflicts:[ ("a", Some (`Eq, 3)) ];
    pkg "d" 1 ~depends:[ [ ("b", Some (`Eq, 2)); ("c", None) ] ];
    pkg "e" 1 ~depends:[ [ ("d", None) ]; [ ("a", Some (`Eq, 3)) ] ];
  ] in
  solve "d" "-removed,-changed" universe [ ("d", None) ];
  solve "d, up to date" "-removed,-notuptodate,-changed" universe [ ("d", None) ];
  solve "e" "-removed,-changed" universe [ ("e", None) ];
  solve "c" "-removed,-notuptodate,-changed" universe [ ("c", None) ];
  (* a larger one: p<i> depends on some version of p<i-1>, versions conflict *)
  let n = 30 in
  let universe = List.concat (List.init n (fun i ->
      List.init 3 (fun v ->
          let v = v + 1 in
          let depends = if i = 0 then [] else [ [ (Printf.sprintf "p%d" (i - 1), Some (`Geq, 1 + (v + i) mod 3)) ] ] in
          let conflicts = if i mod 7 = 3 then [ (Printf.sprintf "p%d" (i - 2), Some (`Eq, 3)) ] else [] in
          pkg (Printf.sprintf "p%d" i) v ~depends ~conflicts ~installed:(v = 1 && i mod 5 = 0)))) in
  let u = Cudf.load_universe universe in
  let req = { Cudf.default_request with install = [ (Printf.sprintf "p%d" (n - 1), None) ] } in
  match Mccs.resolve_cudf "-removed,-notuptodate,-changed" (Cudf.default_preamble, u, req) with
  | None -> print_endline "chain: no solution"
  | Some (_, sol) ->
    let l = Cudf.get_packages ~filter:(fun p -> p.Cudf.installed) sol in
    Printf.printf "chain: %d installed, versions sum %d\n" (List.length l)
      (List.fold_left (fun s p -> s + p.Cudf.version) 0 l)
