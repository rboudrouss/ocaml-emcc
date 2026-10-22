(* fftw3: FFTW (conf-fftw3), double and single precision *)
module F = Fftw3.D
let () =
  let n = 16 in
  let x = F.Array1.create F.complex Bigarray.c_layout n in
  let y = F.Array1.create F.complex Bigarray.c_layout n in
  let plan = F.Array1.dft F.Forward x y in
  for i = 0 to n - 1 do x.{i} <- { Complex.re = cos (2. *. Float.pi *. 3. *. float i /. float n); im = 0. } done;
  F.exec plan;
  for i = 0 to n - 1 do
    let m = Complex.norm y.{i} in if m > 1e-9 then Printf.printf "bin %d: %.6f\n" i m
  done;
  let r = F.Array1.create F.float Bigarray.c_layout n in
  let c = F.Array1.create F.complex Bigarray.c_layout (n / 2 + 1) in
  let p = F.Array1.r2c r c in
  for i = 0 to n - 1 do r.{i} <- float (i mod 4) done;
  F.exec p;
  Printf.printf "r2c dc %.3f, bin4 %.3f\n" c.{0}.Complex.re (Complex.norm c.{4});
  let module S = Fftw3.S in
  let a = S.Array1.create S.complex Bigarray.c_layout 8 and b = S.Array1.create S.complex Bigarray.c_layout 8 in
  let p = S.Array1.dft S.Backward a b in
  for i = 0 to 7 do a.{i} <- if i = 1 then Complex.one else Complex.zero done;
  S.exec p;
  Printf.printf "single: %.4f %.4f\n" b.{2}.Complex.re b.{2}.Complex.im;
  print_endline "done"
