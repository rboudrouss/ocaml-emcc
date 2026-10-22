(* argon2: ctypes-foreign bindings to libargon2 (dlsym at run time) *)
let () =
  match Argon2.hash ~t_cost:2 ~m_cost:1024 ~parallelism:1 ~pwd:"password" ~salt:"somesalt12345678"
          ~kind:Argon2.ID ~hash_len:32 ~encoded_len:128 ~version:Argon2.VERSION_13 with
  | Ok (h, enc) ->
      Printf.printf "hash: %s\nencoded: %s\n" (String.concat "" (List.init (String.length h) (fun i -> Printf.sprintf "%02x" (Char.code h.[i])))) enc;
      Printf.printf "verify ok: %s\n" (match Argon2.verify ~encoded:enc ~pwd:"password" ~kind:Argon2.ID with Ok b -> string_of_bool b | Error e -> Argon2.ErrorCodes.message e);
      Printf.printf "verify bad: %s\n" (match Argon2.verify ~encoded:enc ~pwd:"wrong" ~kind:Argon2.ID with Ok b -> string_of_bool b | Error e -> Argon2.ErrorCodes.message e);
      print_endline "done"
  | Error e -> print_endline (Argon2.ErrorCodes.message e)
