(* digestif (C stubs built by dune), yojson, re, cmdliner: pure OCaml deps. *)
let run name n =
  Printf.printf "hello %s\n" name;
  Printf.printf "sha256(abc) = %s\n" Digestif.SHA256.(to_hex (digest_string "abc"));
  Printf.printf "blake2b(abc) = %s\n" Digestif.BLAKE2B.(to_hex (digest_string "abc"));
  let big = String.make 1_000_000 'x' in
  Printf.printf "md5(1MB) = %s\n" Digestif.MD5.(to_hex (digest_string big));
  let json = `Assoc [ "name", `String name; "n", `Int n; "l", `List [ `Float 1.5; `Bool true; `Null ] ] in
  let s = Yojson.Safe.to_string json in
  Printf.printf "json = %s\n" s;
  Printf.printf "json roundtrip = %b\n" (Yojson.Safe.equal json (Yojson.Safe.from_string s));
  let re = Re.Pcre.re "(\\w+)@(\\w+)\\.com" |> Re.compile in
  let g = Re.exec re "mail: alice@example.com" in
  Printf.printf "re: %s at %s\n" (Re.Group.get g 1) (Re.Group.get g 2)

let () =
  let open Cmdliner in
  let name = Arg.(value & opt string "world" & info [ "name" ]) in
  let n = Arg.(value & pos 0 int 42 & info []) in
  exit (Cmd.eval (Cmd.v (Cmd.info "mixed") Term.(const run $ name $ n)))
