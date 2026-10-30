open Ocaml_emcc

(* A relocatable object, encoded by hand (sizes below 128: one-byte LEBs) *)
let vec items = String.make 1 (Char.chr (List.length items)) ^ String.concat "" items
let name s = vec (List.init (String.length s) (fun i -> String.make 1 s.[i]))
let section id payload = String.make 1 (Char.chr id) ^ String.make 1 (Char.chr (String.length payload)) ^ payload
let b l = String.concat "" (List.map (fun c -> String.make 1 (Char.chr c)) l)

let obj =
  "\000asm\001\000\000\000"
  (* types: 0 = (i32, i32) -> i32, 1 = (f64) -> () *)
  ^ section 1 (vec [ b [ 0x60; 2; 0x7f; 0x7f; 1; 0x7f ]; b [ 0x60; 1; 0x7c; 0 ] ])
  (* imports: a memory, then function 0 = env.ext : 1 *)
  ^ section 2 (vec [ name "env" ^ name "__linear_memory" ^ b [ 2; 0; 1 ]; name "env" ^ name "ext" ^ b [ 0; 1 ] ])
  (* functions 1 and 2 : 0 *)
  ^ section 3 (vec [ b [ 0 ]; b [ 0 ] ])
  ^ section 0
      (name "linking" ^ b [ 2 ]
      ^ section 8
          (vec
             [
               b [ 0; 0; 1 ] ^ name "prim_a";
               b [ 1; 0 ] ^ name "d" ^ b [ 0; 0; 4 ];
               b [ 0; 2; 2 ] ^ name "helper";
               b [ 0; 0x10; 0 ];
               b [ 0; 0x50; 0 ] ^ name "renamed";
             ]))

let run () =
  let sg (s : Wasm.signature) = "(" ^ String.concat ", " s.params ^ ") -> " ^ String.concat ", " s.results in
  let show (s : Wasm.symbol) =
    Printf.sprintf "%s%s%s %s" s.name (if s.defined then "" else " undefined") (if s.local then " local" else "") (sg s.signature)
  in
  Check.strings "Wasm.functions"
    [
      "prim_a (i32, i32) -> i32";
      "helper local (i32, i32) -> i32";
      "ext undefined (f64) -> ";
      "renamed undefined (f64) -> ";
    ]
    (List.map show (Wasm.functions ~what:"obj" obj));
  Check.bool "Wasm.functions: not wasm" true
    (match Wasm.functions ~what:"x" "\127ELF" with exception Failure _ -> true | _ -> false)
