(* A plugin compiled with --cps-stack, as the program: its own deep
   recursion, one going through a function of the program, one of the
   program, Stdlib's fold_right with a closure of the plugin, and an
   exception crossing the CPS frames *)
let n = 200_000

let rec count n = if n = 0 then 0 else 1 + count (n - 1)
let rec down n = App.down down n
let rec raises n = if n = 0 then raise Exit else 1 + raises (n - 1)

let () =
  Printf.printf "pdeep: %d %d %d\n" (count n) (down n) (App.count n);
  Printf.printf "fold_right %d\n" (List.fold_right (fun x acc -> x + acc) (List.init n (fun i -> i mod 3)) 0);
  match raises n with _ -> print_endline "no exception" | exception Exit -> print_endline "caught Exit"
