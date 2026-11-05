(* Recursions which the plugins make deep: one of the program, and one
   alternating between the program and a closure of the plugin *)
let rec count n = if n = 0 then 0 else 1 + count (n - 1)

let down f n = if n = 0 then 0 else 1 + f (n - 1)
