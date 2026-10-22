(* camlzip (no dune: stubs compiled by ocaml-emcc) + the zlib recipe *)
let () =
  let tmp = Filename.get_temp_dir_name () in
  let text = String.concat "\n" (List.init 1500 (fun i -> Printf.sprintf "entry %d %s" i (String.make (i mod 23) 'z'))) in
  let gz = Filename.concat tmp "ocaml-emcc-camlzip.gz" in
  let oc = Gzip.open_out ~level:9 gz in
  Gzip.output_substring oc text 0 (String.length text); Gzip.close_out oc;
  let ic = Gzip.open_in gz in
  let buf = Buffer.create 1024 and chunk = Bytes.create 1000 in
  let rec loop () = let n = Gzip.input ic chunk 0 1000 in if n > 0 then (Buffer.add_subbytes buf chunk 0 n; loop ()) in
  loop (); Gzip.close_in ic; Sys.remove gz;
  Printf.printf "gzip roundtrip: %b\n" (Buffer.contents buf = text);
  let zf = Filename.concat tmp "ocaml-emcc-camlzip.zip" in
  let z = Zip.open_out ~comment:"made by ocaml-emcc" zf in
  Zip.add_entry ~mtime:1e9 text z "a/text.txt";
  Zip.add_entry ~mtime:1e9 ~level:0 "stored" z "b.txt";
  Zip.close_out z;
  let z = Zip.open_in zf in
  Printf.printf "comment: %s\n" (Zip.comment z);
  List.iter
    (fun e ->
      Printf.printf "%s: %d bytes (%d compressed), crc %08lx, same %b\n" e.Zip.filename e.Zip.uncompressed_size
        e.Zip.compressed_size e.Zip.crc
        (Zip.read_entry z e = if e.Zip.filename = "b.txt" then "stored" else text))
    (Zip.entries z);
  Zip.close_in z; Sys.remove zf
