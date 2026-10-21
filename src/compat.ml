(* Stdlib functions newer than OCaml 4.08: ocaml-emcc is installed in the
   switch it targets, so it must build with the oldest supported compiler. *)

let input_all ic =
  let b = Buffer.create 65536 and chunk = Bytes.create 65536 in
  let rec go () =
    let n = input ic chunk 0 65536 in
    if n > 0 then (Buffer.add_subbytes b chunk 0 n; go ())
  in
  go ();
  Buffer.contents b

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> input_all ic)

let with_out_bin path f =
  let oc = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out oc) (fun () -> f oc)

let write_file path s = with_out_bin path (fun oc -> output_string oc s)

let get_int32_be s i = Bytes.get_int32_be (Bytes.unsafe_of_string s) i
let get_int32_le s i = Bytes.get_int32_le (Bytes.unsafe_of_string s) i
let get_int64_be s i = Bytes.get_int64_be (Bytes.unsafe_of_string s) i

let concat_map f l = List.concat (List.map f l)

let rec find_map f = function
  | [] -> None
  | x :: r -> ( match f x with Some _ as y -> y | None -> find_map f r)

let filteri p l =
  let rec go i = function [] -> [] | x :: r -> if p i x then x :: go (i + 1) r else go (i + 1) r in
  go 0 l

(* Filename.quote_command (4.10), for log messages only *)
let quote_command prog args = String.concat " " (List.map Filename.quote (prog :: args))
