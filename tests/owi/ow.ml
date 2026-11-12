(* owi finds the character and the integer for which the program fails:
   '7' (55) and 6.  The C of int_of_string raises Failure on the other
   characters (longjmp: wasm exceptions), caught. *)
let () =
  let c = Emcc_owi.char () in
  let d = try int_of_string (String.make 1 c) with Failure _ -> -1 in
  let x = Emcc_owi.int () in
  Emcc_owi.assume (x >= 0 && x < 100);
  if d > 6 && x * d = 42 then failwith "found"
