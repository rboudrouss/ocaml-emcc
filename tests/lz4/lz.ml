(* lz4: ctypes bindings to liblz4 (conf-liblz4) *)
let () =
  let s = String.concat "" (List.init 300 (fun i -> Printf.sprintf "block %d of text; " (i mod 13))) in
  let c = LZ4.Bytes.compress (Bytes.of_string s) in
  Printf.printf "lz4: %d -> %d (bound %d)\n" (String.length s) (Bytes.length c) (LZ4.compress_bound (String.length s));
  let d = LZ4.Bytes.decompress ~length:(String.length s) c in
  Printf.printf "roundtrip: %b\n" (Bytes.to_string d = s);
  Printf.printf "version >= 10000: %b\n" (LZ4.version_number >= 10000);
  (match LZ4.Bytes.decompress ~length:10 (Bytes.of_string "garbage!") with
   | _ -> print_endline "no error?" | exception LZ4.Corrupted -> print_endline "corrupted detected");
  print_endline "done"
