(* mirage-crypto: symmetric ciphers, a seeded RNG, elliptic curves, RSA *)
let hex s = String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))
let key16 = String.init 16 Char.chr
let key32 = String.init 32 (fun i -> Char.chr (i * 7 land 255))

let () =
  let open Mirage_crypto in
  let k = AES.GCM.of_secret key16 in
  let nonce = String.make 12 '\x01' in
  let ct = AES.GCM.authenticate_encrypt ~key:k ~nonce ~adata:"hdr" "hello, wasm world" in
  Printf.printf "aes-gcm: %s\n" (hex ct);
  (match AES.GCM.authenticate_decrypt ~key:k ~nonce ~adata:"hdr" ct with
   | Some p -> Printf.printf "aes-gcm decrypt: %s\n" p | None -> print_endline "aes-gcm: auth failed");
  let k = AES.CBC.of_secret key16 in
  Printf.printf "aes-cbc: %s\n" (hex (AES.CBC.encrypt ~key:k ~iv:(String.make 16 'i') (String.make 48 'x')));
  let k = AES.CTR.of_secret key32 in
  Printf.printf "aes-ctr: %s\n" (hex (AES.CTR.encrypt ~key:k ~ctr:(AES.CTR.ctr_of_octets (String.make 16 '\000')) "counter mode!"));
  let k = Chacha20.of_secret key32 in
  Printf.printf "chacha20-poly1305: %s\n" (hex (Chacha20.authenticate_encrypt ~key:k ~nonce ~adata:"" "abc"));
  Printf.printf "poly1305: %s\n" (hex (Poly1305.mac ~key:key32 "message"));
  let k = DES.ECB.of_secret (String.make 24 'k') in
  Printf.printf "3des: %s\n" (hex (DES.ECB.encrypt ~key:k "8 bytes!"));
  Printf.printf "xor: %s\n" (hex (Uncommon.xor "abcd" "1234"));
  Printf.eprintf "accelerated: %s\n" (String.concat "," (List.map (function `XOR -> "xor" | `AES -> "aes" | `GHASH -> "ghash") Mirage_crypto.accelerated))

let () =
  (* a deterministic generator *)
  let g = Mirage_crypto_rng.create ~seed:"ocaml-emcc" (module Mirage_crypto_rng.Fortuna) in
  Mirage_crypto_rng.set_default_generator g;
  Printf.printf "fortuna: %s\n" (hex (Mirage_crypto_rng.generate 16));
  let open Mirage_crypto_ec in
  let priv, pub = X25519.gen_key () in
  let priv2, pub2 = X25519.gen_key () in
  let s1 = X25519.key_exchange priv pub2 and s2 = X25519.key_exchange priv2 pub in
  (match s1, s2 with
   | Ok a, Ok b -> Printf.printf "x25519: %s %b\n" (hex a) (a = b)
   | _ -> print_endline "x25519: error");
  let priv, pub = Ed25519.generate () in
  let sg = Ed25519.sign ~key:priv "signed message" in
  Printf.printf "ed25519: %s %b %b\n" (hex sg) (Ed25519.verify ~key:pub sg ~msg:"signed message") (Ed25519.verify ~key:pub sg ~msg:"other");
  let priv, pub = P256.Dsa.generate () in
  let d = Digestif.SHA256.(to_raw_string (digest_string "ecdsa")) in
  let r, s = P256.Dsa.sign ~mask:`No ~key:priv d in
  Printf.printf "p256: %s %s %b\n" (hex r) (hex s) (P256.Dsa.verify ~key:pub (r, s) d);
  let s1, p1 = P384.Dh.gen_key () and s2, p2 = P384.Dh.gen_key () in
  (match P384.Dh.key_exchange s1 p2, P384.Dh.key_exchange s2 p1 with
   | Ok a, Ok b -> Printf.printf "p384 dh: %s %b\n" (hex a) (a = b)
   | _ -> print_endline "p384: error");
  let priv, _ = P521.Dsa.generate () in
  Printf.printf "p521: %s\n" (hex (P521.Dsa.priv_to_octets priv));
  let open Mirage_crypto_pk in
  let priv = Rsa.generate ~bits:1024 () in
  let pub = Rsa.pub_of_priv priv in
  Printf.printf "rsa bits: %d\n" (Rsa.pub_bits pub);
  let sg = Rsa.PKCS1.sign ~hash:`SHA256 ~key:priv (`Message "rsa message") in
  Printf.printf "rsa sig: %s %b\n" (hex sg)
    (Rsa.PKCS1.verify ~hashp:(fun _ -> true) ~key:pub ~signature:sg (`Message "rsa message"));
  let module O = Rsa.OAEP (Digestif.SHA256) in
  let ct = O.encrypt ~key:pub "secret" in
  Printf.printf "oaep: %s\n" (match O.decrypt ~key:priv ct with Some s -> s | None -> "fail");
  let grp = Dh.gen_group ~bits:256 () in
  let (sa, pa) = Dh.gen_key grp and (sb, pb) = Dh.gen_key grp in
  Printf.printf "dh: %b %d\n" (Dh.shared sa pb = Dh.shared sb pa) (Dh.modulus_size grp);
  let dsa = Dsa.generate `Fips1024 in
  let r, s = Dsa.sign ~key:dsa "dsa digest 20 bytes!" in
  Printf.printf "dsa: %b\n" (Dsa.verify ~key:(Dsa.pub_of_priv dsa) (r, s) "dsa digest 20 bytes!");
  Printf.printf "prime: %b %b\n" (Z_extra.pseudoprime (Z.of_string "1000000007")) (Z_extra.pseudoprime (Z.of_int 1000000008))

let () =
  (* the OS entropy source: only check that it works *)
  Mirage_crypto_rng_unix.use_default ();
  Printf.printf "getrandom: %d bytes\n" (String.length (Mirage_crypto_rng.generate 32));
  print_endline "done"
