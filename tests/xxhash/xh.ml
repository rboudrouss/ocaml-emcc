(* xxhash: xxHash's XXH32 and XXH64 (ctypes stubs), one-shot and streaming *)
let () =
  let s = "ocaml-emcc: OCaml bytecode on WebAssembly" in
  Printf.printf "XXH32 %nx seed 7 %nx\n" (XXHash.XXH32.hash s) (XXHash.XXH32.hash ~seed:7n s);
  Printf.printf "XXH64 %Lx seed 7 %Lx\n" (XXHash.XXH64.hash s) (XXHash.XXH64.hash ~seed:7L s);
  let h = XXHash.XXH64.with_state (fun st -> String.iter (fun c -> XXHash.XXH64.update st (String.make 1 c)) s) in
  Printf.printf "streamed %Lx (%b)\n" h (h = XXHash.XXH64.hash s);
  Printf.printf "1 MB %Lx\n" (XXHash.XXH64.hash (String.init (1 lsl 20) (fun i -> Char.chr (i land 255))))
