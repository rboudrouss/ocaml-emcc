(* The executables of a dune project, from `dune describe workspace`:
   ((executables ((names (main)) (modules (((impl (_build/default/bin/main.ml)) ...)))))) *)

type sexp = Atom of string | List of sexp list

let parse s =
  let n = String.length s in
  let rec skip i = if i < n && (s.[i] = ' ' || s.[i] = '\n' || s.[i] = '\t' || s.[i] = '\r') then skip (i + 1) else i in
  let rec value i =
    let i = skip i in
    if s.[i] = '(' then items (i + 1) []
    else if s.[i] = '"' then (
      let b = Buffer.create 16 in
      let rec str j =
        if s.[j] = '"' then (Atom (Buffer.contents b), j + 1)
        else if s.[j] = '\\' then (Buffer.add_char b s.[j + 1]; str (j + 2))
        else (Buffer.add_char b s.[j]; str (j + 1))
      in
      str (i + 1))
    else
      let j = ref i in
      while !j < n && not (String.contains " \n\t\r()\"" s.[!j]) do incr j done;
      (Atom (String.sub s i (!j - i)), !j)
  and items i acc =
    let i = skip i in
    if s.[i] = ')' then (List (List.rev acc), i + 1)
    else
      let v, i = value i in
      items i (v :: acc)
  in
  fst (value 0)

let field name = function
  | List l -> Compat.find_map (function List [ Atom k; v ] when k = name -> Some v | _ -> None) l
  | Atom _ -> None

type exe = { names : string list; dir : string  (** relative to the project root *) }

let strip_build_dir p =
  match String.split_on_char '/' p with "_build" :: _ctx :: rest -> String.concat "/" rest | _ -> p

let executables sexp =
  let entries = match sexp with List l -> l | Atom _ -> [] in
  Compat.concat_map
    (function
      | List [ Atom "executables"; desc ] ->
          let names =
            match field "names" desc with
            | Some (List l) -> List.filter_map (function Atom a -> Some a | List _ -> None) l
            | _ -> []
          in
          let impl =
            match field "modules" desc with
            | Some (List (m :: _)) -> (
                match field "impl" m with Some (List [ Atom p ]) -> Some p | _ -> None)
            | _ -> None
          in
          (match impl with
          | Some p -> [ { names; dir = Filename.dirname (strip_build_dir p) } ]
          | None -> [])
      | _ -> [])
    entries

let run ~dune ~root =
  match Env.output_of dune [ "describe"; "workspace"; "--root"; root ] with
  | Some out -> (try executables (parse out) with _ -> [])
  | None -> []
