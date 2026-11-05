(* A plugin with double translation but without --cps-stack: its own
   recursions are those of the stack, those of the program may be deep *)
let rec down n = App.down down n

let () = Printf.printf "pplain: %d %d\n" (down 1000) (App.count 200_000)
