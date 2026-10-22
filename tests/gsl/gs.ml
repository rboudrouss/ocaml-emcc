(* gsl bindings + the gsl recipe (conf-gsl) *)
let () =
  Printf.printf "J0(5) = %.12g\n" (Gsl.Sf.bessel_J0 5.);
  Printf.printf "gamma(4.5) = %.12g, erf(0.5) = %.12g\n" (Gsl.Sf.gamma 4.5) (Gsl.Sf.erf 0.5);
  (* integral of exp(-x^2) over [0, 1] *)
  let res, _, _ = Gsl.Integration.qng (fun x -> exp (-.(x *. x))) ~a:0. ~b:1. ~epsabs:0. ~epsrel:1e-10 in
  Printf.printf "integral = %.12g\n" res;
  (* linear system *)
  let a = Gsl.Matrix.of_arrays [| [| 4.; 1.; 2. |]; [| 1.; 5.; 3. |]; [| 2.; 3.; 6. |] |] in
  let b = Gsl.Vector.of_array [| 1.; 2.; 3. |] in
  let x = Gsl.Linalg.solve_LU (`M a) (`V b) in
  Printf.printf "x = %s\n" (String.concat " " (Array.to_list (Array.map (Printf.sprintf "%.12g") x)));
  (* random numbers with a fixed seed, and statistics *)
  let rng = Gsl.Rng.make Gsl.Rng.MT19937 in
  Gsl.Rng.set rng 42n;
  let xs = Array.init 1000 (fun _ -> Gsl.Randist.gaussian rng ~sigma:2.) in
  Printf.printf "first %.12g, mean %.10g, sd %.10g\n" xs.(0) (Gsl.Stats.mean xs) (Gsl.Stats.sd xs);
  (* polynomial roots *)
  match Gsl.Poly.solve_cubic ~a:0. ~b:(-7.) ~c:6. with
  | Gsl.Poly.Cubic_3 (a, b, c) -> Printf.printf "roots %.12g %.12g %.12g\n" a b c
  | _ -> print_endline "not 3 roots"
