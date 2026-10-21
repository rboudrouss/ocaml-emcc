(* Pure OCaml: checks that 64-bit bytecode behaves on the wasm32 runtime. *)
let () =
  Printf.printf "Hello from OCaml %s, word_size=%d, int_size=%d\n" Sys.ocaml_version Sys.word_size Sys.int_size;
  Printf.printf "argv[1..] = [%s]\n" (String.concat "; " (List.tl (Array.to_list Sys.argv)));
  Printf.printf "max_int = %d\n" max_int;
  Printf.printf "1 lsl 40 = %d\n" (1 lsl 40);
  Printf.printf "Int64.max_int = %Ld\n" Int64.max_int;
  Printf.printf "0x7fffffff + 1 = %d\n" (0x7fffffff + 1);
  Printf.printf "float: %.17g %s\n" (sqrt 2.) (string_of_float (1. /. 3.));
  let h = Hashtbl.create 16 in
  for i = 0 to 100_000 do Hashtbl.replace h i (i * i) done;
  Printf.printf "Hashtbl: %d entries, h[300] = %d, hash \"abc\" = %d\n" (Hashtbl.length h) (Hashtbl.find h 300) (Hashtbl.hash "abc");
  let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2) in
  Printf.printf "fib 27 = %d\n" (fib 27);
  (try failwith "boom" with Failure s -> Printf.printf "caught Failure %S\n" s);
  let rec deep n = if n = 0 then 0 else 1 + deep (n - 1) in
  Printf.printf "deep recursion: %d\n" (deep 100_000);
  let oc = open_out "/tmp/ocaml-emcc-test.txt" in
  output_string oc "written by wasm\n"; close_out oc;
  let ic = open_in "/tmp/ocaml-emcc-test.txt" in
  Printf.printf "file roundtrip: %s\n" (input_line ic); close_in ic;
  let s = Marshal.to_string [1; 2; 3] [] in
  Printf.printf "marshal roundtrip: %d\n" (List.length (Marshal.from_string s 0 : int list));
  Gc.full_major ();
  Printf.printf "Gc ok, minor collections > 0: %b\n" ((Gc.quick_stat ()).Gc.minor_collections > 0);
  Printf.printf "Printexc: %s\n" (Printexc.to_string Not_found);
  exit 3
