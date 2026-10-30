(* A minimal test harness: no dependency besides the stdlib. *)

let failures = ref 0

let fail name msg = incr failures; Printf.printf "FAIL %s: %s\n%!" name msg

let equal pp name expected got =
  if expected <> got then fail name (Printf.sprintf "expected %s, got %s" (pp expected) (pp got))

let quote s = Printf.sprintf "%S" s
let string = equal quote
let strings = equal (fun l -> "[" ^ String.concat "; " (List.map quote l) ^ "]")
let bool = equal string_of_bool
let option pp = equal (function None -> "None" | Some x -> "Some " ^ pp x)
let string_opt = option quote

(* A fresh empty directory, removed at exit *)
let temp_dir () =
  let d = Filename.temp_file "ocaml-emcc-test" "" in
  Sys.remove d;
  Unix.mkdir d 0o755;
  at_exit (fun () -> ignore (Sys.command ("rm -rf " ^ Filename.quote d)));
  d

let rec mkdir_p d =
  if not (Sys.file_exists d) then (mkdir_p (Filename.dirname d); Unix.mkdir d 0o755)

(* write [path] (relative to [dir]) with [contents], creating directories *)
let file dir path contents =
  let f = Filename.concat dir path in
  mkdir_p (Filename.dirname f);
  Ocaml_emcc.Compat.write_file f contents
