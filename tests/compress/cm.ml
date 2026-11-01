(* OCaml >= 5.1 compresses marshalled data with zstd when its runtime has
   it: the .cmi files, compiler-libs' Compression.  Written with its flag
   (which Marshal does not expose) and read back, and data compressed by
   the native runtime read.  Natively, compression is in a library of
   compiler-libs, which Compression initializes. *)

type extern_flags = No_sharing | Closures | Compat_32 | Compression [@@warning "-37"]

external to_string : 'a -> extern_flags list -> string = "caml_output_value_to_string"

(* a string of 300 digits, compressed natively (OCaml 5.4, zstd) *)
let native = "\132\149\166\189\011\028\1301\001M'(\181/\253\000X\157\000\000`\n\000\000\001,0123456\001\000\"RK\018"

let () =
  Printf.printf "compression supported: %b\n" Compression.compression_supported;
  let v = List.init 2000 (fun i -> (i, string_of_int (i * i))) in
  let s = to_string v [ Compression ] in
  (* 8495a6bd: compressed *)
  Printf.printf "magic: %s\n" (String.concat "" (List.init 4 (fun i -> Printf.sprintf "%02x" (Char.code s.[i]))));
  Printf.printf "smaller than uncompressed: %b\n" (String.length s < String.length (Marshal.to_string v []));
  Printf.printf "read back: %b\n" ((Marshal.from_string s 0 : (int * string) list) = v);
  let n : string = Marshal.from_string native 0 in
  Printf.printf "native data: %d bytes, %s...\n" (String.length n) (String.sub n 0 14)
