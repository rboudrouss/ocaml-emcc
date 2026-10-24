(* Where things are: the opam switch providing the host compiler, the wasm
   sysroot built from it, and the share directory (recipes, tools...). *)

let verbose = ref false

let log fmt = Printf.ksprintf (fun s -> Printf.eprintf "\027[1;34m[ocaml-emcc]\027[0m %s\n%!" s) fmt

let fail fmt = Printf.ksprintf (fun s -> Printf.eprintf "\027[1;31m[ocaml-emcc]\027[0m %s\n%!" s; exit 1) fmt

let getenv_opt v = match Sys.getenv_opt v with Some "" | None -> None | s -> s

(* ------------------------------------------------------------ processes *)

(* the current environment, with [extra] "K=V" bindings overriding *)
let merged_env = function
  | None -> Unix.environment ()
  | Some extra ->
      let keys = List.map (fun kv -> List.hd (String.split_on_char '=' kv)) extra in
      let keep kv = not (List.mem (List.hd (String.split_on_char '=' kv)) keys) in
      Array.append (Array.of_list extra) (Array.of_list (List.filter keep (Array.to_list (Unix.environment ()))))

let run ?env prog args =
  if !verbose then log "%s" (Compat.quote_command prog args);
  let env = merged_env env in
  let pid = Unix.create_process_env prog (Array.of_list (prog :: args)) env Unix.stdin Unix.stdout Unix.stderr in
  match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255

(* Like [run], stderr captured (and returned) instead of shown. *)
let run_capture_stderr ?env prog args =
  if !verbose then log "%s" (Compat.quote_command prog args);
  let tmp = Filename.temp_file "ocaml-emcc" ".err" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let pid = Unix.create_process_env prog (Array.of_list (prog :: args)) (merged_env env) Unix.stdin Unix.stdout fd in
  Unix.close fd;
  let code = match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255 in
  let err = Compat.read_file tmp in
  Sys.remove tmp;
  (code, err)

let run_exn ?env prog args =
  let c = run ?env prog args in
  if c <> 0 then fail "command failed (exit %d): %s" c (Compat.quote_command prog args)

let output_of prog args =
  let ic = Unix.open_process_args_in prog (Array.of_list (prog :: args)) in
  let s = Compat.input_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> Some (String.trim s)
  | _ -> None

let which prog =
  let path = Option.value (getenv_opt "PATH") ~default:"" in
  String.split_on_char ':' path
  |> Compat.find_map (fun d ->
         let p = Filename.concat d prog in
         if Sys.file_exists p && not (Sys.is_directory p) then Some p else None)

(* ------------------------------------------------------------ locations *)

let switch = ref None
let sysroot_override = ref None

(* wasm32 (default): 31-bit ints at run time, see README.
   wasm64 (memory64): the host's 64-bit bytecode runs with native semantics. *)
let target = ref (match Sys.getenv_opt "OCAML_EMCC_TARGET" with Some ("wasm32" | "wasm64" as t) -> t | _ -> "wasm32")

(* --target or OCAML_EMCC_TARGET given: ocaml-emcc.conf does not override. *)
let target_explicit = ref (Sys.getenv_opt "OCAML_EMCC_TARGET" <> None)

(* --recipes DIR (repeatable) *)
let recipe_dirs = ref []

let switch_prefix =
  lazy
    (match !switch with
    | Some s when Filename.is_relative s || not (Sys.file_exists s) -> (
        match output_of "opam" [ "var"; "--switch"; s; "prefix" ] with
        | Some p -> p
        | None -> fail "unknown opam switch %s" s)
    | Some p -> p
    | None -> (
        match getenv_opt "OPAM_SWITCH_PREFIX" with
        | Some p -> p
        | None -> (
            match output_of "opam" [ "var"; "prefix" ] with
            | Some p -> p
            | None -> fail "no opam switch found (use --switch)")))

let host_bin () = Filename.concat (Lazy.force switch_prefix) "bin"

let sysroot () =
  match !sysroot_override with
  | Some s -> s
  | None -> (
      match getenv_opt "OCAML_EMCC_SYSROOT" with
      | Some s -> s
      | None -> Filename.concat (Lazy.force switch_prefix) ("emcc-sysroot/" ^ !target))

let share_dir =
  lazy
    (let exe = Sys.executable_name in
     let exe = if Filename.is_relative exe then Filename.concat (Sys.getcwd ()) exe else exe in
     let bindir = Filename.dirname exe in
     let candidates =
       Option.to_list (getenv_opt "OCAML_EMCC_SHARE")
       @ [
           Filename.concat bindir "../share/ocaml-emcc";
           (* dune exec / _build/default/bin/main.exe inside the repo *)
           Filename.concat bindir "../../../share";
           Filename.concat bindir "../../../../share";
         ]
     in
     match List.find_opt (fun d -> Sys.file_exists (Filename.concat d "driver.sh")) candidates with
     | Some d -> d
     | None -> fail "cannot find the ocaml-emcc share directory (set OCAML_EMCC_SHARE)")

let share () = Lazy.force share_dir

let emcc () =
  match which "emcc" with
  | Some p -> p
  | None -> fail "emcc not found in PATH (source <emsdk>/emsdk_env.sh)"

(* Environment given to the recipe driver and to dune. *)
let driver_env () =
  let p = Project.get () in
  let join l = String.concat ":" (List.filter (( <> ) "") l) in
  let recipes = join (!recipe_dirs @ p.recipes @ Option.to_list (getenv_opt "OCAML_EMCC_RECIPES_PATH")) in
  let cflags = String.concat " " (p.cflags @ Option.to_list (getenv_opt "OCAML_EMCC_EXTRA_CFLAGS")) in
  [
    "OCAML_EMCC_RECIPES_PATH=" ^ recipes;
    "OCAML_EMCC_EXTRA_CFLAGS=" ^ cflags;
    "OCAML_EMCC_SHARE=" ^ share ();
    "OCAML_EMCC_SWITCH_PREFIX=" ^ Lazy.force switch_prefix;
    "OCAML_EMCC_SYSROOT=" ^ sysroot ();
    "OCAML_EMCC_TARGET=" ^ !target;
    "PATH=" ^ host_bin () ^ ":" ^ Option.value (getenv_opt "PATH") ~default:"";
  ]

let driver args =
  run ~env:(driver_env ()) "bash" (Filename.concat (share ()) "driver.sh" :: args)

(* stdout of a driver command, if it succeeds (stderr shown) *)
let driver_output args =
  let tmp = Filename.temp_file "ocaml-emcc" ".out" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let argv = Array.of_list ("bash" :: Filename.concat (share ()) "driver.sh" :: args) in
  let pid = Unix.create_process_env "bash" argv (merged_env (Some (driver_env ()))) Unix.stdin fd Unix.stderr in
  Unix.close fd;
  let code = match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255 in
  let out = String.trim (Compat.read_file tmp) in
  Sys.remove tmp;
  if code = 0 then Some out else None

let sysroot_file rel = Filename.concat (sysroot ()) rel

let toolchain_ready () = Sys.file_exists (sysroot_file "manifest")

(* key=value file written by the `ocaml` recipe *)
let manifest key =
  let f = sysroot_file "manifest" in
  if not (Sys.file_exists f) then None
  else
    Compat.read_file f
    |> String.split_on_char '\n'
    |> Compat.find_map (fun l ->
           match String.index_opt l '=' with
           | Some i when String.sub l 0 i = key -> Some (String.sub l (i + 1) (String.length l - i - 1))
           | _ -> None)

(* Version of the wrappers/findlib files written by `driver.sh toolchain`
   (TOOLCHAIN_VERSION there). *)
let toolchain_version = "8"

let manifest_flags key = Option.fold ~none:[] ~some:Str_util.words (manifest key)
