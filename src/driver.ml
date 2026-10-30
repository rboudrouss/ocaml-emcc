(* share/driver.sh: builds recipes (their `build` function, in bash), and
   the toolchain's wrapper scripts. *)

(* Its environment, also given to dune.  OCAML_EMCC_EXE: the driver runs
   `ocaml-emcc internal ...` for what is done in OCaml. *)
let env () =
  let words l = String.concat " " l in
  [
    "OCAML_EMCC_RECIPES_PATH=" ^ String.concat ":" (Env.extra_recipe_dirs ());
    "OCAML_EMCC_EXTRA_CFLAGS=" ^ words (Toolchain.extra_cflags ());
    "OCAML_EMCC_BASE_CFLAGS=" ^ words (Toolchain.base_cflags ());
    "OCAML_EMCC_TARGET_FLAGS=" ^ words (Toolchain.target_flags ());
    "OCAML_EMCC_STUB_STD=" ^ words (Lazy.force Toolchain.stub_std);
    "OCAML_EMCC_SHARE=" ^ Env.share ();
    "OCAML_EMCC_EXE=" ^ Sys.executable_name;
    "OCAML_EMCC_SWITCH_PREFIX=" ^ Lazy.force Env.switch_prefix;
    "OCAML_EMCC_SYSROOT=" ^ Env.sysroot ();
    "OCAML_EMCC_TARGET=" ^ !Env.target;
    "PATH=" ^ Env.host_bin () ^ ":" ^ Option.value (Env.getenv_opt "PATH") ~default:"";
  ]

let script () = Filename.concat (Env.share ()) "driver.sh"

let run args = Env.run ~env:(env ()) "bash" (script () :: args)

(* stdout of a driver command, if it succeeds (stderr shown) *)
let output args =
  let tmp = Filename.temp_file "ocaml-emcc" ".out" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let argv = Array.of_list ("bash" :: script () :: args) in
  let pid = Unix.create_process_env "bash" argv (Env.merged_env (Some (env ()))) Unix.stdin fd Unix.stderr in
  Unix.close fd;
  let code = match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255 in
  let out = String.trim (Compat.read_file tmp) in
  Sys.remove tmp;
  if code = 0 then Some out else None
