(* Unit tests: no emcc, no network, a fake sysroot and switch. *)

let () =
  let root = Check.temp_dir () in
  Ocaml_emcc.Env.sysroot_override := Some (Filename.concat root "sysroot");
  Ocaml_emcc.Env.switch := Some (Filename.concat root "switch");
  Check.mkdir_p (Filename.concat root "sysroot/stamps");
  Check.mkdir_p (Filename.concat root "switch/.opam-switch/packages");
  Test_stamp.run ();
  if !Check.failures > 0 then (Printf.printf "%d failure(s)\n" !Check.failures; exit 1)
