external int : unit -> int = "caml_emcc_owi_int" [@@noalloc]
external int64 : unit -> int64 = "caml_emcc_owi_int64"
external bool : unit -> bool = "caml_emcc_owi_bool" [@@noalloc]
external char_code : unit -> int = "caml_emcc_owi_char" [@@noalloc]
external assume : bool -> unit = "caml_emcc_owi_assume" [@@noalloc]
external check : bool -> unit = "caml_emcc_owi_check" [@@noalloc]

let char () = Char.unsafe_chr (char_code ())
let string n = String.init n (fun _ -> char ())
