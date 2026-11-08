(* --cps-stack with asyncify (-sASYNCIFY), which compiles without the tail
   calls of WebAssembly: the recursions of jspi, far deeper than the stack
   of a browser, go on in CPS, on the heap, and their returns to the
   continuations bounce on the trampoline, being plain calls.  And
   emscripten_sleep, which asyncify suspends: in a loop, in C calling OCaml
   back, under a deep recursion. *)

external sleep : int -> unit = "ca_sleep"
external twice : (int -> unit) -> unit = "ca_twice"

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
