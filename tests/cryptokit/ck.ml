(* cryptokit: ciphers, hashes, MACs, RSA/DH (zarith), zlib compression *)
open Cryptokit
let hex = transform_string (Hexa.encode ())
let () =
  let key = "0123456789abcdef" in
  Printf.printf "aes-cbc: %s\n" (hex (transform_string (Cipher.aes ~iv:(String.make 16 '\000') key Cipher.Encrypt) "attack at dawn, then retreat!!!!"));
  Printf.printf "aes-gcm: %s\n" (let c = AEAD.aes_gcm ~iv:(String.make 12 'n') key AEAD.Encrypt in let ct, tag = auth_transform_string_detached c "gcm text" in hex ct ^ hex tag);
  Printf.printf "chacha20: %s\n" (hex (transform_string (Cipher.chacha20 ~iv:(String.make 8 'n') (key ^ key) Cipher.Encrypt) "stream cipher"));
  Printf.printf "blowfish: %s\n" (hex (transform_string (Cipher.blowfish key Cipher.Encrypt) "bf test12345678!"));
  Printf.printf "3des: %s\n" (hex (transform_string (Cipher.triple_des (key ^ "01234567") Cipher.Encrypt) "des test"));
  Printf.printf "arcfour: %s\n" (hex (transform_string (Cipher.arcfour key Cipher.Encrypt) "rc4"));
  List.iter (fun (n, h) -> Printf.printf "%s: %s\n" n (hex (hash_string h "The quick brown fox")))
    [ "sha1", Hash.sha1 (); "sha256", Hash.sha256 (); "sha512", Hash.sha512 (); "sha3", Hash.sha3 256;
      "blake2b", Hash.blake2b 512; "blake2s", Hash.blake2s 256; "blake3", Hash.blake3 256; "md5", Hash.md5 (); "ripemd160", Hash.ripemd160 () ];
  Printf.printf "hmac: %s\n" (hex (hash_string (MAC.hmac_sha256 key) "mac me"));
  Printf.printf "siphash: %s\n" (hex (hash_string (MAC.siphash key) "sip"));
  let big = String.concat "" (List.init 200 (fun i -> Printf.sprintf "repeat %d " (i mod 7))) in
  let z = transform_string (Zlib.compress ()) big in
  Printf.printf "zlib: %d -> %d, roundtrip %b\n" (String.length big) (String.length z) (transform_string (Zlib.uncompress ()) z = big);
  let rng = Random.pseudo_rng "seed for a deterministic rng!!!" in
  Printf.printf "prng: %s\n" (hex (Random.string rng 16));
  let priv, pub = RSA.new_key ~rng 1024 in
  let c = RSA.encrypt pub "hello rsa" in
  Printf.printf "rsa: %s\n" (hex c);
  let d = RSA.decrypt priv c in
  Printf.printf "rsa decrypt: %s\n" (String.sub d (String.length d - 9) 9);
  Printf.printf "system rng: %d\n" (String.length (Random.string (Random.system_rng ()) 8));
  Printf.printf "device rng: %d\n" (String.length (Random.string (Random.device_rng "/dev/urandom") 8));
  print_endline "done"
