(* secp256k1-internal: the vendored libsecp256k1 (with gmp) *)
open Libsecp256k1.External
let hex b = String.concat "" (List.init (Bigstring.length b) (fun i -> Printf.sprintf "%02x" (Char.code (Bigstring.get b i))))
let () =
  let ctx = Context.create () in
  let sk = Key.read_sk_exn ctx (Bigstring.of_string (String.init 32 (fun i -> Char.chr (i + 1)))) in
  let pk = Key.neuterize_exn ctx sk in
  Printf.printf "pk: %s\n" (hex (Key.to_bytes ctx pk));
  Printf.printf "pk uncompressed: %s\n" (hex (Key.to_bytes ~compress:false ctx pk));
  let msg = Bigstring.of_string (String.make 32 'm') in
  let sg = Sign.sign_exn ctx ~sk msg in
  Printf.printf "sig: %s\n" (hex (Sign.to_bytes ctx sg));
  Printf.printf "der: %s\n" (hex (Sign.to_bytes ~der:true ctx sg));
  Printf.printf "verify: %b %b\n" (Sign.verify_exn ctx ~pk ~msg ~signature:sg)
    (Sign.verify_exn ctx ~pk ~msg:(Bigstring.of_string (String.make 32 'x')) ~signature:sg);
  let sk2 = Key.add_tweak ctx sk (Bigstring.of_string (String.make 32 '\001')) in
  Printf.printf "tweaked: %s\n" (hex (Key.to_bytes ctx (Key.neuterize_exn ctx sk2)));
  let open Libsecp256k1.Internal in
  let a = Scalar.const ~d7:7l () and b = Scalar.zero () in
  ignore (Scalar.add b a a);
  Printf.printf "scalar: 7+7 even %b, zero %b\n" (Scalar.is_even b) (Scalar.is_zero b);
  print_endline "done"
