(* Primitives implemented in JavaScript (prims.js, ocaml-emcc.conf) *)
open Js_of_ocaml

external add : int -> int -> int = "jp_add"
external greet : Js.js_string Js.t -> Js.js_string Js.t = "jp_greet"
external apply : (int -> int) Js.callback -> int -> int = "jp_apply"
external fail : Js.js_string Js.t -> unit = "jp_fail"
external same : 'a -> 'a = "jp_same"
external six : int -> int -> int -> int -> int -> int -> Js.js_string Js.t = "jp_six" "jp_six"

let () =
  Printf.printf "add: %d\n" (add 40 2);
  Printf.printf "greet: %s\n" (Js.to_string (greet (Js.string "wörld")));
  Printf.printf "apply: %d\n" (apply (Js.wrap_callback (fun x -> x * 3)) 5);
  (try fail (Js.string "boom") with Js_error.Exn e -> Printf.printf "error: %s\n" (Js_error.message e));
  let l = [ 1; 2 ] in
  Printf.printf "same: %b\n" (same l == l);
  Printf.printf "six: %s\n" (Js.to_string (six 1 2 3 4 5 6));
  let config = Js.Unsafe.runtime_value "jp_config" in
  Printf.printf "config: %s %d\n" (Js.to_string (Js.Unsafe.get config "name")) (Js.Unsafe.get config "version")
