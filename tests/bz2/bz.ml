(* bz2 bindings + the libbz2 recipe (conf-libbz2) *)
let () =
  let text = String.concat "\n" (List.init 2000 (fun i -> Printf.sprintf "line %d: %s" i (String.make (i mod 37) 'x'))) in
  let b = Bytes.of_string text in
  let z = Bz2.compress ~block:9 b 0 (Bytes.length b) in
  Printf.printf "%d -> %d bytes, digest %s\n" (Bytes.length b) (Bytes.length z) (Digest.to_hex (Digest.bytes z));
  let u = Bz2.uncompress z 0 (Bytes.length z) in
  Printf.printf "roundtrip: %b\n" (Bytes.equal u b);
  (* channels *)
  let file = Filename.concat (Filename.get_temp_dir_name ()) "ocaml-emcc-bz2-test.bz2" in
  let oc = open_out_bin file in
  let bz = Bz2.open_out oc in
  Bz2.write bz b 0 (Bytes.length b); Bz2.close_out bz; close_out oc;
  let ic = open_in_bin file in
  let bz = Bz2.open_in ic in
  let buf = Buffer.create 1024 and chunk = Bytes.create 4096 in
  (try
     while true do
       let n = Bz2.read bz chunk 0 4096 in
       if n = 0 then raise End_of_file;
       Buffer.add_subbytes buf chunk 0 n
     done
   with End_of_file -> ());
  Bz2.close_in bz; close_in ic; Sys.remove file;
  Printf.printf "file roundtrip: %b\n" (Buffer.contents buf = text)
