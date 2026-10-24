open Ctypes
module T = Pt.C.Types
module F = Pt.C.Functions

let () =
  Printf.printf "sizeof agrees with C: %b\n"
    (sizeof T.pt = Unsigned.Size_t.to_int (F.pt_size ()));
  let s = make T.pt in
  setf s T.c 'A';
  setf s T.l (Signed.Long.of_int 1000);
  setf s T.p null;
  setf s T.d 7.5;
  Printf.printf "C reads the fields: %s\n" (Signed.Long.to_string (F.pt_sum (addr s)));
  F.pt_fill (addr s);
  Printf.printf "OCaml reads the fields: %c %s %b %g\n" (getf s T.c)
    (Signed.Long.to_string (getf s T.l))
    (ptr_compare (getf s T.p) (to_voidp (addr s)) = 0)
    (getf s T.d)
