(* ctypes-foreign: C functions bound at run time through libffi (the libffi
   recipe, conf-libffi), OCaml callbacks passed to C, structs by value *)
open Ctypes
open Foreign

let strlen = foreign "strlen" (string @-> returning size_t)
let labs = foreign "labs" (long @-> returning long)
let pow = foreign "pow" (double @-> double @-> returning double)
let strtol = foreign "strtol" (string @-> ptr (ptr char) @-> int @-> returning long)

let qsort =
  foreign "qsort"
    (ptr void @-> size_t @-> size_t @-> funptr (ptr void @-> ptr void @-> returning int) @-> returning void)

type div_t
let div_t : div_t structure typ = structure "div_t"
let quot = field div_t "quot" int
let rem = field div_t "rem" int
let () = seal div_t
let div = foreign "div" (int @-> int @-> returning div_t)

let () =
  Printf.printf "strlen = %d\n" (Unsigned.Size_t.to_int (strlen "hello, wasm"));
  Printf.printf "labs = %s\n" (Signed.Long.to_string (labs (Signed.Long.of_int (-42))));
  Printf.printf "pow = %g\n" (pow 2. 10.);
  let endp = allocate (ptr char) (from_voidp char null) in
  let n = strtol "1234xyz" endp 10 in
  Printf.printf "strtol = %s, rest = %s\n" (Signed.Long.to_string n)
    (coerce (ptr char) string !@endp);
  let d = div 47 5 in
  Printf.printf "div 47 5 = %d rem %d\n" (getf d quot) (getf d rem);
  (* qsort with an OCaml comparison: a libffi closure *)
  let a = CArray.of_list int [ 5; 3; 9; 1; 7; 2; 8 ] in
  let calls = ref 0 in
  let cmp x y = incr calls; compare !@(from_voidp int x) !@(from_voidp int y) in
  qsort (to_voidp (CArray.start a)) (Unsigned.Size_t.of_int (CArray.length a))
    (Unsigned.Size_t.of_int (sizeof int)) cmp;
  Printf.printf "sorted: %s (callback called: %b)\n"
    (String.concat " " (List.map string_of_int (CArray.to_list a))) (!calls > 0)
