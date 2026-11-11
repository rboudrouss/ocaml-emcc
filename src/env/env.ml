(* Where things are: the opam switch providing the host compiler, the wasm
   sysroot built from it, and the share directory (recipes, tools...). *)

let verbose = ref false

let log fmt = Printf.ksprintf (fun s -> Printf.eprintf "\027[1;34m[ocaml-emcc]\027[0m %s\n%!" s) fmt

(* Raised by [fail], once the message is shown: the CLI exits with 1, a
   caller may carry on (Layouts.shadow) *)
exception Failed

let fail fmt = Printf.ksprintf (fun s -> Printf.eprintf "\027[1;31m[ocaml-emcc]\027[0m %s\n%!" s; raise Failed) fmt

let getenv_opt v = match Sys.getenv_opt v with Some "" | None -> None | s -> s

(* ------------------------------------------------------------ processes *)

(* the current environment, with [extra] "K=V" bindings overriding *)
let merged_env = function
  | None -> Unix.environment ()
  | Some extra ->
      let keys = List.map (fun kv -> List.hd (String.split_on_char '=' kv)) extra in
      let keep kv = not (List.mem (List.hd (String.split_on_char '=' kv)) keys) in
      Array.append (Array.of_list extra) (Array.of_list (List.filter keep (Array.to_list (Unix.environment ()))))

(* [out]: where its stdout goes (stderr for commands whose own stdout is a
   result) *)
(* [cwd]: the directory it runs in *)
let spawn ?cwd prog args env inp out err =
  let here = Sys.getcwd () in
  Option.iter Sys.chdir cwd;
  Fun.protect ~finally:(fun () -> Sys.chdir here)
    (fun () -> Unix.create_process_env prog (Array.of_list (prog :: args)) env inp out err)

(* dune, one at a time between the ocaml-emcc processes of the machine
   (dune refuses to build while another holds the build directory: links
   of the same project running at the same time) *)
let one_dune prog f =
  if Filename.basename prog <> "dune" then f ()
  else
    let fd = Unix.openfile (Filename.concat (Filename.get_temp_dir_name ()) "ocaml-emcc-dune.lock") [ Unix.O_RDWR; Unix.O_CREAT ] 0o666 in
    let rec lock () = try Unix.lockf fd Unix.F_LOCK 0 with Unix.Unix_error (Unix.EINTR, _, _) -> lock () in
    lock ();
    Fun.protect ~finally:(fun () -> Unix.close fd) f

let run ?env ?cwd ?(out = Unix.stdout) prog args =
  if !verbose then log "%s" (Compat.quote_command prog args);
  let env = merged_env env in
  one_dune prog @@ fun () ->
  let pid = spawn ?cwd prog args env Unix.stdin out Unix.stderr in
  match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255

(* Like [run], its stdout and stderr written to [file] *)
let run_logged ?env ?cwd file prog args =
  if !verbose then log "%s > %s" (Compat.quote_command prog args) file;
  one_dune prog @@ fun () ->
  let fd = Unix.openfile file [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
  let pid = spawn ?cwd prog args (merged_env env) Unix.stdin fd fd in
  Unix.close fd;
  match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255

(* Like [run], stderr captured (and returned) instead of shown. *)
let run_capture_stderr ?env prog args =
  if !verbose then log "%s" (Compat.quote_command prog args);
  let tmp = Filename.temp_file "ocaml-emcc" ".err" in
  let code =
    one_dune prog @@ fun () ->
    let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
    let pid = Unix.create_process_env prog (Array.of_list (prog :: args)) (merged_env env) Unix.stdin Unix.stdout fd in
    Unix.close fd;
    match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255
  in
  let err = Compat.read_file tmp in
  Sys.remove tmp;
  (code, err)

let run_exn ?env ?cwd ?out prog args =
  let c = run ?env ?cwd ?out prog args in
  if c <> 0 then fail "command failed (exit %d): %s" c (Compat.quote_command prog args)

(* How many commands [run_all_exn] runs at a time: $OCAML_EMCC_JOBS, else
   the number of processors *)
let jobs () =
  match Option.bind (getenv_opt "OCAML_EMCC_JOBS") int_of_string_opt with
  | Some n -> max 1 n
  | None -> (
      let ic = try Some (Unix.open_process_args_in "/bin/sh" [| "/bin/sh"; "-c"; "nproc 2>/dev/null || sysctl -n hw.ncpu" |]) with _ -> None in
      match ic with
      | None -> 1
      | Some ic ->
          let n = try int_of_string_opt (String.trim (input_line ic)) with End_of_file -> None in
          ignore (Unix.close_process_in ic);
          max 1 (Option.value n ~default:1))

(* The commands [(prog, args, done_)], [jobs ()] at a time, [done_] called
   once each succeeds; the first failure, once the others have ended *)
let run_all_exn cmds =
  let jobs = jobs () in
  let running = Hashtbl.create 16 in
  let failed = ref None in
  let rec wait () = try Unix.wait () with Unix.Unix_error (Unix.EINTR, _, _) -> wait () in
  let wait_one () =
    let pid, st = wait () in
    match Hashtbl.find_opt running pid with
    | None -> ()
    | Some (prog, args, done_) -> (
        Hashtbl.remove running pid;
        match st with
        | Unix.WEXITED 0 -> done_ ()
        | Unix.WEXITED c -> if !failed = None then failed := Some (c, prog, args)
        | _ -> if !failed = None then failed := Some (255, prog, args))
  in
  List.iter
    (fun (prog, args, done_) ->
      if !failed = None then (
        while Hashtbl.length running >= jobs do wait_one () done;
        if !verbose then log "%s" (Compat.quote_command prog args);
        let pid = spawn prog args (merged_env None) Unix.stdin Unix.stdout Unix.stderr in
        Hashtbl.replace running pid (prog, args, done_)))
    cmds;
  while Hashtbl.length running > 0 do wait_one () done;
  match !failed with
  | Some (c, prog, args) -> fail "command failed (exit %d): %s" c (Compat.quote_command prog args)
  | None -> ()

let which prog =
  let path = Option.value (getenv_opt "PATH") ~default:"" in
  String.split_on_char ':' path
  |> Compat.find_map (fun d ->
         let p = Filename.concat d prog in
         if Sys.file_exists p && not (Sys.is_directory p) then Some p else None)

(* (before OCaml 4.12, open_process_args_in does not search PATH) *)
let output_of prog args =
  let exe = if String.contains prog '/' then prog else Option.value (which prog) ~default:prog in
  one_dune prog @@ fun () ->
  let ic = Unix.open_process_args_in exe (Array.of_list (prog :: args)) in
  let s = Compat.input_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> Some (String.trim s)
  | _ -> None

(* stdout of a command if it succeeds, its stderr discarded unless
   [errors] *)
let capture ?env ?cwd ?(errors = false) prog args =
  if !verbose then log "%s" (Compat.quote_command prog args);
  let tmp = Filename.temp_file "ocaml-emcc" ".out" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  let err = if errors then Unix.stderr else Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
  (* a missing program fails like a failing one: the callers fall back *)
  let pid = try Some (spawn ?cwd prog args (merged_env env) Unix.stdin fd err) with Unix.Unix_error _ -> None in
  Unix.close fd;
  if not errors then Unix.close err;
  let code = match pid with None -> 127 | Some pid -> ( match snd (Unix.waitpid [] pid) with Unix.WEXITED c -> c | _ -> 255) in
  let out = Compat.read_file tmp in
  Sys.remove tmp;
  if code = 0 then Some out else None

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

(* The recipe directories, searched in order: --recipes, the project's,
   $OCAML_EMCC_RECIPES_PATH, then the builtin ones. *)
let extra_recipe_dirs () =
  let env = String.split_on_char ':' (Option.value (getenv_opt "OCAML_EMCC_RECIPES_PATH") ~default:"") in
  List.filter (( <> ) "") (!recipe_dirs @ (Project.get ()).recipes @ env)

let recipes_path () = extra_recipe_dirs () @ [ Filename.concat (share ()) "recipes" ]

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

let manifest_flags key = Option.fold ~none:[] ~some:Str_util.words (manifest key)
