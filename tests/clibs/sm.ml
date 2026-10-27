(* checkseum (C variant, through optint: its 32-bit code on wasm32) and
   bigstringaf (C stubs on bigarrays) *)
let () =
  let c = Checkseum.Crc32.digest_string "hello world" 0 11 Checkseum.Crc32.default in
  Printf.printf "crc32: %08lx\n" (Optint.to_int32 c);
  let c = Checkseum.Adler32.digest_string "hello world" 0 11 Checkseum.Adler32.default in
  Printf.printf "adler32: %08lx\n" (Optint.to_int32 c);
  let c = Checkseum.Crc32c.digest_string "hello world" 0 11 Checkseum.Crc32c.default in
  Printf.printf "crc32c: %08lx\n" (Optint.to_int32 c);
  let c = Checkseum.Crc24.digest_string "hello world" 0 11 Checkseum.Crc24.default in
  Printf.printf "crc24: %08lx\n" (Optint.to_int32 c);
  let b = Bigstringaf.of_string ~off:0 ~len:11 "hello world" in
  let b2 = Bigstringaf.create 11 in
  Bigstringaf.blit b ~src_off:0 b2 ~dst_off:0 ~len:11;
  Bigstringaf.blit_from_string "HELLO" ~src_off:0 b2 ~dst_off:0 ~len:5;
  Printf.printf "bigstringaf: %s %d %d %d\n" (Bigstringaf.to_string b2)
    (compare (Bigstringaf.memcmp b 0 b2 0 11) 0) (compare (Bigstringaf.memcmp_string b 6 "world" 0 5) 0)
    (Bigstringaf.memchr b 0 'w' 11);
  Printf.printf "bigstringaf get: %x %x %lx %Lx\n" (Bigstringaf.get_int16_le b 0) (Bigstringaf.get_int16_be b 0)
    (Bigstringaf.get_int32_be b 0) (Bigstringaf.get_int64_le b 0);
  print_endline "done"
