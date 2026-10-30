(* The C toolchain: emcc, and the flags every piece of C code (runtime,
   stubs, C libraries) is compiled with.  driver.sh gets them from the
   environment (Driver.env). *)

let emcc () = Env.emcc ()
let emar () = Filename.concat (Filename.dirname (emcc ())) "emar"

let emcc_version =
  lazy (match Env.capture (emcc ()) [ "-dumpversion" ] with Some v -> String.trim v | None -> Env.fail "emcc -dumpversion failed")

(* wasm32 runs the host's 64-bit bytecode with 31-bit ints; wasm64
   (memory64) matches its semantics exactly (see README).  Every piece of C
   code must agree on these:
    -fno-strict-overflow  pointer arithmetic may wrap: stops LLVM from
                          folding negative offsets (Tag_val, Hd_val: p[-8])
                          into the unsigned offset of wasm64 loads, which
                          traps.
    -sSUPPORT_LONGJMP=wasm  OCaml raises exceptions from C with longjmp; the
                          wasm EH implementation avoids routing every call
                          made by the interpreter through JS invoke_*
                          trampolines.
    -fwasm-exceptions     C++ exceptions with the same wasm EH instructions
                          (minisat); emscripten's JS ones cannot be thrown
                          with SUPPORT_LONGJMP=wasm.  No effect on C code. *)
let target_flags () =
  (if !Env.target = "wasm64" then [ "-m64" ] else [])
  @ [ "-fno-strict-overflow"; "-sSUPPORT_LONGJMP=wasm"; "-fwasm-exceptions" ]

let opt () = Option.value (Env.getenv_opt "OCAML_EMCC_OPT") ~default:"-O2"

(* What the toolchain wrappers and the link step record; extra flags are
   added on top at each use (recipes, stubs in tools/ocamlc). *)
let base_cflags () = Str_util.words (opt ()) @ [ "-fno-strict-aliasing"; "-fwrapv" ] @ target_flags ()

(* cflags: of ocaml-emcc.conf, then $OCAML_EMCC_EXTRA_CFLAGS *)
let extra_cflags () =
  (Project.get ()).cflags @ Option.fold ~none:[] ~some:Str_util.words (Env.getenv_opt "OCAML_EMCC_EXTRA_CFLAGS")

let cflags () = base_cflags () @ extra_cflags ()

(* The C standard of the host compiler, when newer than emcc's default
   (gnu17): stub sources generated at build time follow it (ctypes writes
   `bool`, a keyword only since C23, the default of gcc >= 15). *)
let stub_std =
  lazy
    (let cc =
       match Env.capture (Filename.concat (Env.host_bin ()) "ocamlc") [ "-config-var"; "c_compiler" ] with
       | Some c when Str_util.words c <> [] -> Str_util.words c
       | _ -> [ "cc" ]
     in
     let src = Filename.temp_file "ocaml-emcc" ".c" in
     Compat.write_file src "__STDC_VERSION__\n";
     let out = Env.capture (List.hd cc) (List.tl cc @ [ "-x"; "c"; "-E"; "-P"; src ]) in
     Sys.remove src;
     let digits = Buffer.create 8 in
     String.iter (fun c -> if c >= '0' && c <= '9' then Buffer.add_char digits c) (Option.value out ~default:"");
     match int_of_string_opt (Buffer.contents digits) with Some v when v >= 202311 -> [ "-std=gnu23" ] | _ -> [])

(* Flags to compile OCaml stubs against the runtime headers of the target *)
let stub_cflags () =
  cflags () @ Lazy.force stub_std
  @ [ "-I" ^ Env.sysroot_file "lib/ocaml"; "-I" ^ Env.sysroot_file "include"; "-D_FILE_OFFSET_BITS=64" ]

(* The environment recipes run in (driver.sh exports the same), for the
   builds of stubs run from OCaml: makefiles called by dune rules see it *)
let build_env () =
  let cflags = String.concat " " (cflags ()) in
  [ "CFLAGS=" ^ cflags; "CXXFLAGS=" ^ cflags; "LDFLAGS=" ^ String.concat " " (target_flags ()); "EMAR=" ^ emar () ]
  @ Switch.opam_env ()
