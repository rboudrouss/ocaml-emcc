(* glpk: linear programming (conf-glpk) *)
open Glpk
let () =
  (* maximise 10x + 6y + 4z s.t. x+y+z <= 100, 10x+4y+5z <= 600, 2x+2y+6z <= 300 *)
  let lp = make_problem Maximize [| 10.; 6.; 4. |]
      [| [| 1.; 1.; 1. |]; [| 10.; 4.; 5. |]; [| 2.; 2.; 6. |] |]
      [| (-.infinity, 100.); (-.infinity, 600.); (-.infinity, 300.) |]
      [| (0., infinity); (0., infinity); (0., infinity) |] in
  set_message_level lp 0;
  scale_problem lp;
  use_presolver lp true;
  simplex lp;
  let prim = get_col_primals lp in
  Printf.printf "z = %.4f  x = %.4f %.4f %.4f\n" (get_obj_val lp) prim.(0) prim.(1) prim.(2);
  print_endline "done"
