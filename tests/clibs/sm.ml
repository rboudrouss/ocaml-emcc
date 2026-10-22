(* small C-stub libraries: sha, checkseum, bigstringaf, mtime/ptime clocks, eqaf *)
let () =
  Printf.printf "sha1: %s\n" (Sha1.to_hex (Sha1.string "abc"));
  Printf.printf "sha256: %s\n" (Sha256.to_hex (Sha256.string "abc"));
  Printf.printf "sha512: %s\n" (Sha512.to_hex (Sha512.string "abc"));
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
    (Bigstringaf.memcmp b 0 b2 0 11) (Bigstringaf.memcmp_string b 6 "world" 0 5)
    (Bigstringaf.memchr b 0 'w' 11);
  Printf.printf "bigstringaf get: %x %x %lx %Lx\n" (Bigstringaf.get_int16_le b 0) (Bigstringaf.get_int16_be b 0)
    (Bigstringaf.get_int32_be b 0) (Bigstringaf.get_int64_le b 0);
  let t0 = Mtime_clock.now () in
  let c = Mtime_clock.counter () in
  ignore (Sys.opaque_identity (List.init 10000 Fun.id));
  let t1 = Mtime_clock.now () in
  Printf.printf "mtime monotonic: %b, counter >= 0: %b\n" (Mtime.is_later t1 ~than:t0 || Mtime.equal t1 t0)
    (Mtime.Span.compare (Mtime_clock.count c) Mtime.Span.zero >= 0);
  let now = Ptime_clock.now () in
  Printf.printf "ptime after 2020: %b\n" (Ptime.is_later now ~than:(Option.get (Ptime.of_date (2020, 1, 1))));
  Printf.printf "ptime tz offset is some: %b\n" (Ptime_clock.current_tz_offset_s () <> None);
  Printf.printf "eqaf: %b %b %d\n" (Eqaf.equal "secret" "secret") (Eqaf.equal "secret" "secreT")
    (Eqaf.compare_be "abc" "abd");
  print_endline "done"
