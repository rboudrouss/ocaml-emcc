(* Recursions far deeper than the stack of a browser (500 KB to 1 MB: some
   thousands of nested calls of the compiled code), which run on new
   stacks of the engine with JSPI: plain calls, allocation (the GC runs in
   between), Stdlib's non-tail fold_right, and an exception crossing all
   the stacks.  And emscripten_sleep, which JSPI suspends as asyncify
   would: in a loop, in C calling OCaml back, under a deep recursion. *)

external sleep : int -> unit = "jp_sleep"
external twice : (int -> unit) -> unit = "jp_twice"

let n = 200_000

let rec depth k = if k = 0 then 0 else 1 + depth (k - 1)
let rec build k = if k = 0 then [] else (k mod 7) :: build (k - 1)
let rec down k = if k = 0 then raise Exit else 1 + down (k - 1)

let () =
  Printf.printf "depth %d\n" (depth n);
  let l = build n in
  Printf.printf "length %d\n" (List.length l);
  (* (100 000: the bytecode interpreter's own stack, 8 MB with OCaml 4.14,
     holds no more of its frames, natively too) *)
  Printf.printf "fold_right %d\n" (List.fold_right ( + ) (build 100_000) 0);
  (match down n with _ -> print_endline "no exception" | exception Exit -> print_endline "caught Exit");
  Printf.printf "again %d\n" (depth n);
  for i = 1 to 3 do sleep 5; Printf.printf "frame %d\n%!" i done;
  twice (fun i -> Printf.printf "callback %d\n%!" i);
  let rec deep k = if k = 0 then (sleep 1; 0) else 1 + deep (k - 1) in
  Printf.printf "slept at depth %d\n" (deep n)
