(* System C libraries reached through opam conf-* packages: mlmpfr
   (conf-mpfr -> mpfr + gmp) and zlib (conf-zlib).  Versions are not printed:
   the wasm build may use a newer release than the host's. *)

let () =
  let pi = Mlmpfr.const_pi 200 in
  Printf.printf "pi (200 bits) = %s\n" (Mlmpfr.get_formatted_str ~size:50 pi);
  let two = Mlmpfr.make_from_str ~prec:200 "2" in
  Printf.printf "sqrt 2        = %s\n" (Mlmpfr.get_formatted_str ~size:50 (Mlmpfr.sqrt ~prec:200 two));
  let x = Mlmpfr.mul ~prec:200 pi (Mlmpfr.make_from_float ~prec:200 1e10) in
  Printf.printf "pi * 1e10     = %s\n" (Mlmpfr.get_formatted_str ~size:40 x)

let bigstring_of_string s =
  let b = Bigarray.(Array1.create char c_layout (String.length s)) in
  String.iteri (fun i c -> b.{i} <- c) s;
  b

let string_of_bigstring b n = String.init n (fun i -> b.{i})

let run_flate t input =
  t.Zlib.in_buf <- bigstring_of_string input;
  t.in_ofs <- 0;
  t.in_len <- String.length input;
  let out = Bigarray.(Array1.create char c_layout 65536) in
  t.out_buf <- out;
  t.out_ofs <- 0;
  t.out_len <- Bigarray.Array1.dim out;
  (match Zlib.flate t Zlib.Finish with
   | Zlib.Stream_end -> ()
   | _ -> failwith "flate did not finish");
  string_of_bigstring out t.out_ofs

let () =
  let text = String.concat "" (List.init 200 (fun i -> Printf.sprintf "line %d of a compressible text\n" (i mod 7))) in
  Printf.printf "adler32       = %08lx\n" (Zlib.adler32 Zlib.adler32_empty text);
  let packed = run_flate (Zlib.create_deflate ~level:9 ()) text in
  let unpacked = run_flate (Zlib.create_inflate ()) packed in
  Printf.printf "deflate       : %d -> %d bytes, round trip %s\n" (String.length text)
    (String.length packed) (if unpacked = text then "ok" else "BROKEN")
