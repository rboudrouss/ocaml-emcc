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
    (match Wasm.functions ~what:"x" "\127ELF" with exception Failure _ -> true | _ -> false);
  (* --owi: a function of type () -> i32, running an i32.atomic.rmw.add
     (offset 4), an i32.atomic.load and an atomic.fence *)
  let atomics ~memory body =
    "\000asm\001\000\000\000"
    ^ section 1 (vec [ b [ 0x60; 0; 1; 0x7f ] ])
    ^ section 3 (vec [ b [ 0 ] ])
    ^ section 5 (vec [ b memory ])
    ^ section 10 (vec [ b (List.length body + 1 :: 0 :: body) ])
  in
  let body = [ 0x41; 8; 0x41; 1; 0xFE; 0x1E; 2; 4; 0x1A; 0x41; 8; 0xFE; 0x10; 2; 0; 0xFE; 0x03; 0; 0x0B ] in
  let lowered, n = Lower_atomics.lower (atomics ~memory:[ 0; 1 ] body) in
  Check.string "Lower_atomics.lower: count" "3" (string_of_int n);
  let expected =
    "\000asm\001\000\000\000"
    (* (i32, i32) -> i32 added *)
    ^ section 1 (vec [ b [ 0x60; 0; 1; 0x7f ]; b [ 0x60; 2; 0x7f; 0x7f; 1; 0x7f ] ])
    ^ section 3 (vec [ b [ 0 ]; b [ 1 ] ])
    ^ section 5 (vec [ b [ 0; 1 ] ])
    ^ section 10
        (vec
           [
             (* a call to function 1, an i32.load, no fence *)
             b [ 14; 0; 0x41; 8; 0x41; 1; 0x10; 1; 0x1A; 0x41; 8; 0x28; 2; 0; 0x0B ];
             (* the address, the old value (local 2) plus the operand, stored *)
             b [ 23; 1; 1; 0x7f; 0x20; 0; 0x20; 0; 0x28; 2; 4; 0x21; 2; 0x20; 2; 0x20; 1; 0x6A; 0x36; 2; 4; 0x20; 2; 0x0B ];
           ])
  in
  Check.string "Lower_atomics.lower: module" (String.escaped expected) (String.escaped lowered);
  Check.string "Lower_atomics.lower: none left" "0" (string_of_int (snd (Lower_atomics.lower lowered)));
  Check.bool "Lower_atomics.lower: shared memory refused" true
    (match Lower_atomics.lower (atomics ~memory:[ 3; 1; 1 ] body) with exception Lower_atomics.Unsupported _ -> true | _ -> false)
