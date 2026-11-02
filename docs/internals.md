# How ocaml-emcc works

## The build

1. **Runtime** (`setup`, the `ocaml` recipe): the sources of the switch's
   compiler are configured with `emconfigure`, then `libcamlrun.a` and the
   C parts of `unix`, `str` and `runtime_events` are built and installed in
   the sysroot with the wasm headers. A findlib toolchain (`wasm32` or
   `wasm64`) is written for dune.
2. **Bytecode**: the host's own `ocamlc`, ppx, menhir and installed `.cma`
   files are used unchanged.
3. **dune -x**: in the wasm context, an `ocamlc` wrapper rewrites
   `ocamlc -config`, so dune compiles stubs with emcc and the wasm headers.
   An `ocamlmklib` replacement builds the `lib*.a` with `emar`, and
   `(modes exe)` executables come out as plain bytecode
   (`-output-complete-exe` is intercepted). Package rules that call
   `ocamlmklib`, `pkg-config` or `llvm-config` themselves get the wasm
   versions, which come first in dune's `PATH`; the wasm `ocamlmklib`
   hands host objects to the host tool. The C compiler of this context
   turns the executables it links into node scripts, so that build rules
   can run them.
4. **Dependencies**: the bytecode's `DLLS` section names the stub libraries
   (`dllzarith`...), and each `dll<x>` maps to a wasm `lib<x>.a`. A missing
   one is built from the opam package that installed `dll<x>.so`, by the
   first of:
   1. a recipe with the package's name;
   2. the package's own dune rules (`dune -x`), as for digestif;
   3. the C files behind each stub archive of the package's native build,
      with its `-I` flags: for packages without dune (glpk), when `dune -x`
      fails, or when an archive was built by a host tool (ocaml-lua runs
      `make` in its copy of Lua);
   4. every `.c` file of the package that includes `<caml/...>`.

   `c_library_flags` are only used by custom links, which a bytecode build
   does not do. So the toolchain's `ocamlc` records those of every linked
   `.cma` in the sysroot, and `link` builds the missing ones: the stub
   library of the opam package that installed `dllX.so` (libraries built
   with `ocamlmklib -custom`, such as stb_image, are only named there), or
   the recipe providing `libX.a`.
5. **Link**: a primitive table is generated with only the primitives the
   bytecode uses, so wasm-ld drops the rest. The bytecode, without its
   `DLLS`/`DLPT` sections, is embedded in the module and `argv[0]` points
   to it (the `ocamlc -custom` trick), so `Sys.argv` looks native.

## Compiled mode

With `--compiled`, `link` (step 5 above) runs `c_of_ocaml PROG.bc -o
PROG.c` instead of embedding the bytecode, and `c_of_ocaml --runtime-files
DIR` for the runtime support of the generated code (`camlc.h`,
`camlc_runtime.c`). On wasm64, c_of_ocaml gets `--word-size 64`, for
63-bit integers. Both C files are compiled with the flags of the runtime
and linked with `libcamlrun.a` and the stub libraries, in place of
`main.c` and the primitive table. `camlc_runtime.c` defines `main` and the
functions of the runtime's `callback.c`, so that the interpreter is never
linked.

The C code is compiled with `-mtail-call`, so that its tail calls are
tail calls of WebAssembly. Asyncify does not support them: when the link
flags contain `-sASYNCIFY` and not `-sJSPI`, ocaml-emcc leaves the flag
out, and tail calls become ordinary calls. The link exports `malloc` and
`free`, as the file system of the interpreter does, since the JavaScript
code of some stubs (libffi, for ctypes) calls them.

The generated C calls the primitives directly, declared with the arity of
their call sites. The stubs whose definition differs get adapters, as with
the primitive table (see [signature adapters](#signature-adapters)), and
the C code is compiled again with `-DNAME=ocaml_emcc_adapt__NAME` for
each of them. The bytecode is not
needed at run time: nothing is embedded, preloaded or written next to the
output.

The compiled functions run on the stack of the wasm engine, about 1 MB on
node's main thread. Under node, `share/runtime/node_stack.js` (a
`--pre-js`) starts the same script in a worker thread with a large stack
(`resourceLimits.stackSizeMb`), stops the main thread from instantiating
the module (`Module.instantiateWasm`), and passes the worker's exit code
on. A `RangeError` for the call stack is reported as an uncaught
`Stack_overflow`.

## Standalone modules

A `.wasm` without JavaScript has no file system to embed the bytecode in.
Its sections become the C arrays of a generated `bytecode.c` (`#embed`),
and `main.c` starts the program with `caml_startup_code`, as the C file of
`ocamlc -output-obj` does: `CODE`, `DATA`, the section table of that
compiler for the toplevel and Dynlink (`SYMB`, `CRCS`, and `PRIM` before
5.0), and the debug events of `DBUG`, relocated and gathered by `link`
into what the runtime would build from the executable file (backtraces
keep their locations).

## WASI

emscripten's standalone libc already reads, writes and closes files, and
reads clocks, arguments and the environment, with WASI calls. But opening
and `stat`ing a file are stubs that fail (EPERM, ENOSYS) whatever the host,
and the rest of the file system (`unlink`, `rename`, `getcwd`,
`readdir`...), sockets and `system` are imports of emscripten's
JavaScript. `--wasi` adds `share/runtime/wasi.c`, which implements these
system calls with WASI as wasi-libc does, and links with `-sPURE_WASI`,
which removes emscripten's last import (memory growth notifications).

`setjmp`/`longjmp` (`-sSUPPORT_LONGJMP=wasm`) and C++ exceptions are
compiled into emscripten's default encoding of wasm exceptions, the legacy
one, which WASI hosts do not implement: binaryen translates the module to
the standard one (exnref) as emcc finishes it
(`-sBINARYEN_EXTRA_PASSES=--translate-to-exnref,--emit-exnref`).

When the program's own C (its stubs, `-l` archives, `c_library_flags`)
defines one of the functions of `wasi.c`, `compat.c` or `dlsym.c`
(`__syscall_getcwd` or `getaddrinfo` for instance), `link` leaves
ocaml-emcc's out and says so: the program's definition is the one linked.

## Threads

All the C code (runtime, recipes, stubs) is compiled with `-pthread`:
atomics, and thread-local variables (`caml_state` in OCaml 5) in a TLS
block. Objects built with and without it cannot be mixed: one built
without reads the thread-local variables of the others as plain globals
("no domain lock held"), and a link with a shared memory refuses it. Such
objects still link into a program without shared memory, where the TLS
block is a plain data segment and the atomics act on an unshared memory:
the link decides, and `--threads` adds `-pthread` to it. The stamps of the
recipes record it (`abi=pthread`): those built before are built again.

With emscripten's glue, threads are web workers, and `main` runs in one
too (`-sPROXY_TO_PTHREAD`), unless the program uses js_of_ocaml's
primitives (the page's thread, for the DOM; `-sPTHREAD_POOL_SIZE` workers
started before `main` in a browser). Without it, the JavaScript thread runs
the program, and the other threads' system calls on files (emscripten's
file system lives there) only when the program waits: one computing, or
waiting for a flag another thread sets after a `prerr_endline`, never let
them run; neither did OCaml 4.14's tick thread, whose `select` went there
(it now sleeps in place: no descriptors). Under node, `node_threads_stack.js`
gives each worker the large stack `node_stack.js` gives the program
otherwise. OCaml's threads and domains are detached:
an exiting one asks the main thread to take its worker back with a
`postMessage`, which a JavaScript thread blocked in `Thread.join` never
receives; `share/runtime/threads.c` and `threads.js` route it through
emscripten's proxying queue, which it runs while it waits.
The system calls of the other threads on files run on the main thread
through that queue too, which emscripten's `poll` and `select` do not
run (they never wait on the main thread): a main thread looping on them
(`Lwt_main` waiting for a job's `stat`) never ran it. `threads.c`'s `poll`
and `select` run it first. No worker pool under node, which starts a
worker at once (the pool cost 200 ms and 140 MB at startup).

A WASI module has no glue to start its threads: `share/runtime/wasi_threads.c`
implements the JavaScript functions of emscripten's pthread library the C
library imports (`__pthread_create_js`...) with wasi-threads' `thread-spawn`,
the host running the module's `wasi_thread_start` export (stack pointer
first, in assembly, then TLS and the thread's state) in a new instance on
a new thread. Its pipes are protected by a lock, a blocking read or a
`poll` waits for another thread to write.

### Threads in the libraries

The C libraries and stubs are compiled with `-pthread` as well, but the
program decides at link time: those whose threads are only locks or
thread-local variables have them (they are needed with domains), those
that would start threads by themselves do not, as a program linked
without `--threads` cannot.

| where | threads | why |
|-------|---------|-----|
| mpfr, OpenSSL, libevent (`libevent_pthreads`), pixman, fontconfig | yes | locks and thread-local variables only |
| liblo | yes | its server thread (`lo_server_thread`) fails without `--threads`, as `Thread.create` does |
| lwt (`lwt_unix_start_job`) | when the program has them | decided when the job starts (`emscripten_has_threading_support`): without, the job runs synchronously |
| async_unix (`In_thread`) | when the program has them | it tries to start a thread, and runs the jobs synchronously when it cannot |
| ffmpeg, OpenBLAS, argon2 | no | they start threads themselves (a codec's, at `avcodec_open2`; a pool at startup; parallel lanes), which would fail without `--threads` |
| fftw3 | no | its threads are a separate library (`libfftw3_threads`) its binding does not use |
| `-fopenmp` | no (dropped) | emscripten has no OpenMP runtime |
| OCaml 5.0 to 5.2 | no domains | the number of domains is a constant (their minor heaps are allocated at startup); threads work |

## JavaScript primitives

When the bytecode links js_of_ocaml's stub libraries (`jsoo_runtime_stubs`,
`js_of_ocaml_stubs`), or with `--js-file`, `link` compiles
`share/runtime/jsoo.c` in and links the emscripten library
`share/runtime/jsoo.js` (`--js-library`) instead of those libraries, also
named by the `-cclib` flags of the bytecode.

A JavaScript value lives in a table of `jsoo.js` and is, in OCaml, a custom
block holding its index, whose finalizer frees the entry. `undefined`,
`null`, `true`, `false` and `globalThis` have fixed indexes and one block
each. C and JavaScript exchange values as a pair (tag, double): a number, an
index, or the address of a GC root holding an OCaml value (wrapped in an
`OcamlValue` object on the JavaScript side, which releases the root through a
`FinalizationRegistry`). The functions of `jsoo.js` take and return only
`int`s and `double`s, so nothing changes on wasm64 (no `BigInt`). A result
is an int: an index, or a code whose payload `jsoo.js` stores at an address
`jsoo.c` gave it once (an integer, a root, an exception).

A callback is a JavaScript function holding a root on the OCaml closure.
When called, it calls the exported `ocaml_emcc_js_callback`, which fetches
the arguments one by one and applies the closure with `caml_callbackN_exn`.
An OCaml exception leaving it is thrown as an `OcamlExn` holding a root on
it, and raised again in OCaml when it gets back to a primitive. The first
callback calls `runtimeKeepalivePush()`. The `exit` at the end of the main
program then only unwinds: the runtime stays alive for the event loop
(under node, the process ends once it is empty). An `ExitStatus` leaving a
callback ends the node process.

For `--js-file`, `link` lists the names the files provide, generates for each
primitive of the program that no library defines a C stub with the prototype
of its call site, calling `ocaml_emcc_js_prim("NAME", n, args)`, and a
JavaScript table `ocamlEmccJsPrims` of the files' functions, after them in
the `--pre-js` files.

## Plugins

`link --dynlink` runs `c_of_ocaml --dynlink`, which registers every
compilation unit of the program by name, and links with `-sMAIN_MODULE=2`.
A main module only exports the symbols it is told to
(`-sEXPORTED_FUNCTIONS=@exports.json`). `--export-dynamic` does not do it:
emscripten does not see the data symbols, which a side module imports
through its `GOT.mem`. The list is computed before the link. `link` reads
with `llvm-nm` what each member of the archives defines and needs, takes
the members a link of the objects takes, as wasm-ld does (any order), and
exports what they and the runtime support objects define, plus a few
functions of libc and libm the generated code may call. The generated C of
the program is not exported, since plugins look its units up by name.
Exporting a symbol of an archive member makes wasm-ld link it, hence the
exact computation: camlc_runtime.o replaces some members of libcamlrun.a,
which would otherwise come along.

The thread-local variables of the program (OCaml 5's `caml_state`,
c_of_ocaml's state: everything is compiled with `-pthread`) are exported
as offsets in its TLS block, which emscripten only turns into addresses in
the GOT of a program with threads. Without, `share/runtime/dynlink.js`
does it before `main`, with the TLS base of the main thread
(`ocaml_emcc_tls_base` of dynlink.c) and the names `link` reads from the
program's `dylink.0` section once linked.

`plugin` runs c_of_ocaml on the `.cma` or `.cmo`, compiles the C with
`-fPIC`, and links it with `-sSIDE_MODULE=1`. Its only export is
`camlc_plugin_init`. `Emcc_dynlink.loadfile` (share/runtime/dynlink.c)
`dlopen`s it (`RTLD_LOCAL`) and calls `camlc_plugin_init` from the
primitive, as it must run inside an OCaml call. `load_url` uses
`emscripten_dlopen`, which fetches and compiles the module asynchronously.
Its callback resumes the OCaml continuation with the handle, which then
calls the entry point through another primitive. The library's own stubs
only fail, and `link` replaces them by dynlink.c, as it does for
js_of_ocaml's.

## Signature adapters

A wasm indirect call traps on any signature mismatch, while native code
ignores extra arguments: OCaml calls zarith's `ml_z_init()` with one
argument, for instance. The arity of each call site is read from the
bytecode (`C_CALLn`), the signature of each definition from the wasm
objects of the libraries (the symbol table of their `linking` section and
the types of their functions, `src/link/wasm.ml`), the first in link
order, and an adapter is generated for each one that differs, before the
link. A function never called, calling each primitive directly, makes
wasm-ld report the mismatches left (a stub in an object that could not be
read, LTO bitcode for instance).

## ctypes layouts

ctypes lays C types out (struct fields, `sizeof`, arrays) with sizes it
generated when it was built (`ctypes_primitives.ml`), and bindings that
generate their type descriptions (`Cstubs_structs`, yaml, posix-stat)
print the offsets of the structs from a C program. Built on the 64-bit
host, both are those of LP64 and of the host's libc: wrong for wasm32,
where `long`, `size_t` and pointers have 4 bytes, and for the structs of
the libc on both targets, as emscripten's musl does not lay them out as
glibc does (`st_size` of `struct stat` on wasm64 is glibc's `st_mtime`).
A 32-bit host would not do either: i386 aligns `double` and `int64_t` to 4
bytes in structs, wasm32 to 8.

So `build` and `link` rebuild ctypes and the packages of the
program that depend on it (found from the program's `CRCS` section and
the opam dependencies), once per switch, package version and version of
the toolchain's wrappers (`src/packages/shadow.ml`). Their OCaml libraries are installed in
`<sysroot>/lib/findlib`, which the toolchain searches before the switch.
`build` then builds the bytecode against them, and also rebuilds the
libraries of the switch that ocamlc finds compiled against the host's
build of one of them (ctypes-foreign imports `Ctypes_primitives`).

Each package is built with dune, in a single context on the target's
toolchain (without the host context of `dune -x`, whose executables dune
would run instead): its OCaml generators are bytecode run by the host's
`ocamlrun` with the host's stub DLLs, its C generators are compiled by
emcc into node scripts, and dune-configurator gets the answers of the
target.

Packages built without dune cannot be rebuilt this way. When one of them
does not generate structs or unions (its types are constants), the host's
build is kept as it is.

## Jane Street's configuration

Jane Street's libraries choose some of their OCaml code when they are
built, with ppx_optcomp and the `config.h` of jst-config (`[%%import
"config.h"]`), which dune-configurator computes from the C configuration of
the host: `JSC_ARCH_SIXTYFOUR` is defined there. On wasm32, time_now and
core then treat an `Int63` as an `int`, where Base, which chooses at run
time, represents it as an `int64` (`Sys.word_size` is 32): the 64-bit code
reaches `caml_int64_div` with an `int` (a crash in async).

So on wasm32, jst-config and the packages copying its `config.h` into an
OCaml library are rebuilt for the target as ctypes is, and then those
compiled against an interface that differs there (core's: the whole async
stack). dune-configurator compiles its tests with `-I` the host's
standard library, whose `caml/config.h` is the host's: the toolchain's
emcc wrapper replaces it by the runtime's. Of the `config.h` built for
wasm32, only `JSC_ARCH_SIXTYFOUR` and `JSC_ARCH_BIG_ENDIAN` are kept, the
rest is the host's: emscripten's other answers make combinations Jane
Street's code never meets (`JSC_LINUX_EXT` without `JSC_EVENTFD`:
linux_ext then declares eventfd's primitives in OCaml, and its C defines
them only with both), while core_unix's patches give the primitives of
the host's configuration to emscripten, failing with `ENOSYS`. The
toolchain finds this `config.h` before the host's
(`%{lib:jst-config:config.h}`), for the C stubs too. On wasm64 the host's
configuration is kept as it is.

## dune's `(ctypes)` stanza

dune links the generators of its `(ctypes)` stanza natively only
([ocaml/dune#13650](https://github.com/ocaml/dune/issues/13650)), which
the wasm context cannot do, having no `ocamlopt`. So a project or package
that uses the stanza (`(using ctypes ...)` in its `dune-project`) is built
by a dune patched to link them as custom bytecode when there is no
`ocamlopt`, the linkage dune already uses for ppx drivers and cinaps
(`share/tools/dune/ctypes-linkage.patch`). It is built from the sources of
the switch's dune, once per version, into `<sysroot>/libexec/dune`. The
OCaml generators then run on the host's `ocamlrun`, and the C program
printing the offsets of the structs is compiled by emcc: the layouts are
those of the target. The fix was proposed upstream in
[ocaml/dune#7431](https://github.com/ocaml/dune/pull/7431), closed unmerged
for lack of a test: a cram test hiding `ocamlopt`, as
`test/blackbox-tests/test-cases/byte-code-only.t` does, would do.

## ctypes-foreign

A static wasm program has no `dlsym`, so `link` exports the C functions and
variables whose names appear as string literals in the program, and links
a `dlopen`/`dlsym` that looks them up among the module's exports.
ctypes-foreign also needs the `threads` library, which the `ocaml` recipe
builds single-threaded.

## Flags used for all C code

- `-fno-strict-overflow`: works around an LLVM bug on wasm64, which folds
  `p[-8]` (`Tag_val`) into an unsigned load offset that traps
- `-sSUPPORT_LONGJMP=wasm`: OCaml raises exceptions from C with longjmp,
  and the JS implementation would route every primitive call through JS
- `-fwasm-exceptions`: C++ exceptions with the same wasm instructions
  (emscripten's JS exceptions cannot be thrown alongside)
- `-pthread` when compiling (the wrapper adds it, the recipes get it in
  `CFLAGS`), not when linking: see [Threads](#threads)

## OCaml versions

The `ocaml` recipe works around these issues:

| version | issue | fix |
|---------|-------|-----|
| 4.08    | `caml_debug_info` defined in two files (needs `-fcommon`, which wasm lacks) | `patches/4.08/`: made `extern` in `backtrace.c` |
| 4.x     | `Tag_val` indexes with an unsigned `-sizeof(value)`: out-of-bounds wasm32 load | `patches/4.x/` (fixed upstream in 5.0) |
| < 4.12  | `afl.c` needs `shmat`, missing from emscripten's libc | weak stub (`share/runtime/compat.c`) |
| ≥ 4.14  | `runtime/sak` is a build-time tool | built with the host `cc` |
| ≤ 4.11  | otherlibs ignore the configure `CFLAGS` | target flags passed in `CC` |
| 5.x     | no `sigaltstack` in emscripten ("Failed to allocate signal stack") | `ac_cv_func_sigaction=no` |
| 5.x     | minor heap committed with `mmap(MAP_FIXED)` ("Failed to create main domain") | `patches/5.0/`, `patches/5.1+/`: committed with `mprotect`, as on Cygwin |
| 5.x     | the minor heaps of all the possible domains (16 in wasm32, 128 in wasm64) reserved at startup, which emscripten's `mmap` allocates and clears: 13 MB more memory and ~10 ms in wasm32, 300 MB and ~130 ms in wasm64 | `patches/5.3+/`: the default of `OCAMLRUNPARAM=d` comes from the program (`caml_emcc_max_domains`, `compat.c`): 1, 8 with `--threads`; `patches/5.0-5.2/`: a single domain (`Max_domains` is a constant there) |
| ≥ 5.3   | without POSIX signals, a new domain has no signal stack, which its thread takes for a failure ("Failed to create domain: signal stack") | `patches/5.3+/`: not checked |
| 5.0     | configure only compiles its `pthread_getaffinity_np` test: undefined at link time | `patches/5.0/`: not called |
| 5.0     | otherlibs stub archives without the `byt` suffix (5.1) | `libunix.a`, `libcamlstr.a`... |
| ≥ 5.5   | `caml_byte_program_mode` and `caml_runtime_standard_library_default` come from the file ocamlc generates | weak definitions (`compat.c`) |
| ≥ 5.5   | DLL names in the bytecode start with `-` or `:` | prefix removed (`Bytecode.dlls`) |
| all     | `sigsuspend` missing (unix) | weak stub |
| all     | wasm engines optimize a function for its next calls only (no on-stack replacement): the interpreter, called once, stays in V8's baseline tier (Liftoff), twice as slow; and its `setjmp` wraps each of its calls in an exception handler | `patches/4.x/`, `patches/5.x/`: it returns to its caller every 2^20 polls (`CHECK_SIGNALS`) and is called again; the caller does the `setjmp` and calls it again to handle an exception raised by C |
| all, wasm32 | `ARCH_ALIGN_DOUBLE` (`alignof(double)` is 8): float accesses through memcpy, some stubs refuse to build (gsl) | undefined, as for i686: wasm loads doubles at any alignment |
| all     | systhreads disabled (no pthreads) | `libthreads.a` built anyway, single-threaded |
| all, wasm32 | integer literals beyond 31 bits in the DATA section ("input_value: integer too large") | `patches/4.x/`, `patches/5.x/`: wrapped to 31 bits while DATA is read (`intern.c`, `startup_byt.c`), from the file (`caml_main`) or from memory (`caml_startup_code`, standalone modules) |
| all     | a program started by `caml_startup_code` (standalone modules) reads its debug events from the executable file, which does not exist: backtraces without locations | `patches/all/`: `backtrace_byt.c` takes them from memory when `main.c` gives them (`caml_emcc_debug_events`), unchanged otherwise |
| all, wasm64 | stubs pass `int` dimensions to `caml_ba_alloc_dims`, read as `intnat` (stb_image: a corrupted heap) | `patches/headers/`: the installed `bigarray.h` converts each one |

Patches go in `share/recipes/ocaml/patches/`: `all/`, `4.x/` or `5.x/`,
`5.1+/`, `<major>.<minor>/` (applied in this order), and `headers/` for the
headers installed for the stubs only. Compilers before 4.08 are not
supported: their build has no autoconf `configure`, and their bytecode,
marshal and runtime layouts differ from what the link step reads.
