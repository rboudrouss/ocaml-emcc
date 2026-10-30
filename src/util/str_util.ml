(* The first position of [sub] in [s] from [from] *)
let find_from s from sub =
  let n = String.length s and m = String.length sub in
  let rec at i k = k = m || (s.[i + k] = sub.[k] && at i (k + 1)) in
  let rec go i = if i + m > n then None else if at i 0 then Some i else go (i + 1) in
  go from

let find s sub = find_from s 0 sub

let starts_with ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let words s = String.split_on_char ' ' s |> List.filter (( <> ) "")
