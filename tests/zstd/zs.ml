(* zstd bindings (ctypes generated stubs) + the zstd recipe (conf-zstd) *)
let () =
  let text = String.concat "\n" (List.init 3000 (fun i -> Printf.sprintf "%d,%s,%d" i (if i mod 3 = 0 then "fizz" else "buzz") (i * i))) in
  List.iter
    (fun level ->
      let z = Zstd.compress ~level text in
      let u = Zstd.decompress (String.length text) z in
      Printf.printf "level %d: %d -> %d bytes, size in frame %d, roundtrip %b\n" level (String.length text)
        (String.length z) (Zstd.get_decompressed_size z) (u = text))
    [ 1; 3; 19 ]
