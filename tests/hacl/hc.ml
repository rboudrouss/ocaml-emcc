(* hacl-star: HACL*'s verified C (vendored, built by its own Makefile)
   through ctypes stubs, portable implementations only (no SIMD) *)
open Hacl_star.Hacl

let hex b = String.concat "" (List.map (fun c -> Printf.sprintf "%02x" (Char.code c)) (List.of_seq (Bytes.to_seq b)))
let b s = Bytes.of_string s
let seq n f = Bytes.init n (fun i -> Char.chr (f i land 255))
let opt = function Some x -> hex x | None -> "none"

let () =
  let msg = b "The quick brown fox jumps over the lazy dog" in
  Printf.printf "sha2-256  %s\n" (hex (SHA2_256.hash msg));
  Printf.printf "sha2-512  %s\n" (hex (SHA2_512.hash msg));
  Printf.printf "sha3-256  %s\n" (hex (SHA3_256.hash msg));
  Printf.printf "shake128  %s\n" (hex (Keccak.shake128 ~msg ~size:40));
  Printf.printf "blake2b   %s\n" (hex (Blake2b_32.hash ~key:(b "key") msg 32));
  Printf.printf "blake2s   %s\n" (hex (Blake2s_32.hash msg 32));
  Printf.printf "hmac      %s\n" (hex (HMAC_SHA2_256.mac ~key:(b "secret") ~msg));
  Printf.printf "poly1305  %s\n" (hex (Poly1305_32.mac ~key:(seq 32 (fun i -> i)) ~msg));
  let prk = HKDF_SHA2_256.extract ~salt:(b "salt") ~ikm:(b "input key") in
  Printf.printf "hkdf      %s\n" (hex (HKDF_SHA2_256.expand ~prk ~info:(b "info") ~size:42));
  (* AEAD: encrypt, decrypt, a corrupted tag is refused *)
  let key = seq 32 (fun i -> 3 * i) and iv = seq 12 (fun i -> i + 1) and ad = b "header" in
  let ct, tag = Chacha20_Poly1305_32.encrypt ~key ~iv ~ad ~pt:msg in
  Printf.printf "chacha    %s %s\n" (hex ct) (hex tag);
  (match Chacha20_Poly1305_32.decrypt ~key ~iv ~ad ~ct ~tag with
   | Some pt -> Printf.printf "decrypt   %s\n" (Bytes.to_string pt) | None -> print_endline "decrypt   failed");
  Bytes.set tag 0 (Char.chr (Char.code (Bytes.get tag 0) lxor 1));
  Printf.printf "forged    %b\n" (Chacha20_Poly1305_32.decrypt ~key ~iv ~ad ~ct ~tag = None);
  (* X25519 *)
  let ska = seq 32 (fun i -> 7 * i + 1) and skb = seq 32 (fun i -> 11 * i + 5) in
  let pka = Curve25519_51.secret_to_public ~sk:ska and pkb = Curve25519_51.secret_to_public ~sk:skb in
  Printf.printf "x25519    %s\n" (hex pka);
  Printf.printf "ecdh      %s %b\n" (opt (Curve25519_51.ecdh ~sk:ska ~pk:pkb))
    (Curve25519_51.ecdh ~sk:ska ~pk:pkb = Curve25519_51.ecdh ~sk:skb ~pk:pka);
  (* Ed25519 *)
  let sk = seq 32 (fun i -> 255 - i) in
  let pk = Ed25519.secret_to_public ~sk in
  let signature = Ed25519.sign ~sk ~msg in
  Printf.printf "ed25519   %s\n          %s\n" (hex pk) (hex signature);
  Printf.printf "verify    %b %b\n" (Ed25519.verify ~pk ~msg ~signature)
    (Ed25519.verify ~pk ~msg:(b "another message") ~signature);
  (* P-256 ECDSA with a fixed nonce, and K-256 *)
  let sk = seq 32 (fun i -> i + 0x20) and k = seq 32 (fun i -> 0x40 + i) in
  (match P256.dh_initiator ~sk with
   | None -> print_endline "p256      no public key"
   | Some pk ->
     let s = P256.sign ~sk ~msg ~k in
     Printf.printf "p256      %s\n          %s\n" (hex (P256.raw_to_compressed pk)) (opt s);
     Printf.printf "verify    %b\n" (match s with Some signature -> P256.verify ~pk ~msg ~signature | None -> false));
  (match K256.secret_to_public ~sk with
   | None -> print_endline "k256      no public key"
   | Some pk ->
     let s = K256.sign ~sk ~msg:(SHA2_256.hash msg) ~k in
     Printf.printf "k256      %s %s\n" (hex (K256.raw_to_compressed pk)) (opt s));
  (* NaCl box *)
  let n = seq 24 (fun i -> i * 5) in
  match NaCl.box ~pt:msg ~n ~pk:pkb ~sk:ska with
  | None -> print_endline "box       failed"
  | Some ct ->
    Printf.printf "box       %s\n" (hex ct);
    Printf.printf "box_open  %s\n" (match NaCl.box_open ~ct ~n ~pk:pka ~sk:skb with
      | Some pt -> Bytes.to_string pt | None -> "failed")
