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
the opam dependencies), once per switch and package version
(`src/packages/shadow.ml`). Their OCaml libraries are installed in
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
- no `-pthread` (lwt asks for it): the program is single-threaded, and
  with it `caml_state` would be a thread-local variable, unlike in the
  runtime

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
| 5.x     | configure adds `-pthread`: runtime and stubs disagree on `caml_state` ("no domain lock held") | `PTHREAD_CFLAGS=-D_REENTRANT` given to configure, which AX_PTHREAD keeps |
| 5.x     | minor heap committed with `mmap(MAP_FIXED)` ("Failed to create main domain") | `patches/5.0/`, `patches/5.1+/`: committed with `mprotect`, as on Cygwin |
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
