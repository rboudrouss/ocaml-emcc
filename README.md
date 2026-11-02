# ocaml-emcc

Compile OCaml programs **together with their C stubs** to WebAssembly, for
node, browsers and WASI hosts.

Your program and its dependencies (zarith/gmp, unix, str, digestif, your own
`foreign_stubs`, a C library cloned from GitHub...) end up in one
emscripten module. Unlike js_of_ocaml / wasm_of_ocaml, no C stub has to be
rewritten in JavaScript, so FFI-heavy code works as is.

But the program runs as bytecode, interpreted by an
`ocamlrun` compiled to wasm, so it is much slower than the same program
compiled by js_of_ocaml or wasm_of_ocaml, which compile OCaml itself. If your
project is pure OCaml, or its C stubs already have JavaScript
implementations, use those instead. ocaml-emcc is for code whose C you
cannot or do not want to rewrite.

There is an experimental
[compiled mode](#compiled-mode) that approaches wasm_of_ocaml performances by compiling the bytecode to C before running emscripten.

## Quick start

```sh
opam install ocaml-emcc             # or opam pin add ocaml-emcc git+https://github.com/rboudrouss/ocaml-emcc.git
source /path/to/emsdk/emsdk_env.sh  # emcc in PATH

ocaml-emcc build main.js            # in your dune project
node main.js                        # or load main.js in a web page
```

`ocaml-emcc build main.js` finds the dune executable named `main`, builds a
wasm OCaml runtime from the sources of your switch's compiler (the first
time only), compiles the C stubs of the program and of its dependencies
with emcc, and writes `main.js` and `main.wasm`.

## Requirements

- An opam switch with **OCaml 4.08 or later** (4.x or 5.x).
- The sources of the compiler and of the packages with C stubs, which
  ocaml-emcc rebuilds. They are fetched once with `opam source` (network
  access, a version still in the opam repository), unless the switch kept
  them (`--keep-build-dir` or `OPAMKEEPBUILDDIR=true` when installing).
- The emscripten SDK, with `emcc` in `PATH` (tested with emsdk 6.0.11).
  Standalone `.wasm` outputs need emsdk 4.0 or later (clang 19, for
  `#embed`).
- dune 3.11 or later, except for projects built without dune (see
  [Without dune](#without-dune)).

Everything ocaml-emcc builds (the runtime, C libraries, rebuilt packages)
lives in `$OPAM_SWITCH_PREFIX/emcc-sysroot/` and goes away with the switch.

## Building

```sh
ocaml-emcc build main.js                      # the executable `main`, wherever it is
ocaml-emcc build bin/main.js                  # the executable bin/main
ocaml-emcc build dist/app.js --exe bin/main   # any other output path
```

The executable built is the one at the same path as the output, else the
only executable of the project with that name. `--exe DIR/NAME` names it
explicitly. Any `(modes ...)` works, `byte` is not needed.

The extension of the output decides what is written:

| output | what it is | runs in |
|--------|------------|---------|
| `main.js` (+ `main.wasm`) | the module and emscripten's JavaScript glue | node, browsers |
| `main.html` (+ `.js`, `.wasm`) | the same, plus a minimal emscripten page | browsers |
| `main.wasm` | a standalone module, without JavaScript | hosts providing emscripten's imports |
| `main.wasm` with `--wasi` | a module importing only WASI functions | wasmtime, node's WASI, other WASI hosts (see [WASI](#wasi)) |
| `main.wasm` with `--wasix` | `--wasi`, with WASIX's sockets | wasmer (see [WASI](#wasi)) |

A standalone `.wasm` without `--wasi` still imports emscripten functions
(file operations other than read and write, `getcwd`, sockets...), which
its host has to provide. See [standalone WebAssembly](https://v8.dev/blog/emscripten-standalone-wasm).

Note that `--wasi` uses emscripten's **experimental flag** `-sPURE_WASI`.

The most common options are `--target wasm64` (see
[wasm32 or wasm64](#wasm32-or-wasm64)), `-O -Oz` (default `-O2`),
`--stack-size 16MB` (default 8MB), `-l LIB` and `-L DIR` for extra
libraries, and `--emcc-flag F`. Arguments after `--` are passed to emcc.
`ocaml-emcc help` lists all the commands and options, and project
defaults go in [`ocaml-emcc.conf`](#configuration).

## Running

### In node

```sh
node main.js arg1 arg2
```

The bytecode is embedded in the `.wasm`, and the program behaves like a
native executable: it gets the arguments, the exit code, and the standard
streams of the node process as bytes (`node main.js < in.bin > out.bin`
works). Its files are in emscripten's in-memory file system, unless it is
built with `--node-fs`, the build then only runs in node, sees the real
file system and the environment variables (`Sys.getenv`), and the bytecode
is written next to `main.js` instead of being embedded.
Libraries that read files installed with them (why3's
`share/why3`, frama-c's share directory, found with dune-site) need
`--node-fs`.

### In a browser

The same `main.js` and `main.wasm` work in a web page. The `Module` object
gives the arguments and receives the output:

```html
<script>
  var Module = {
    arguments: ["arg1"],
    print: s => console.log(s),       // stdout
    printErr: s => console.error(s),  // stderr
  };
</script>
<script src="main.js"></script>
```

- Don't declare global `out` or `err` variables in the page because emscripten's
  script declares them.
- `Module.print`, `Module.printErr` and `Module.stdin` handle lines of
  text rather than bytes. They take precedence over node's streams too.
- `-- -sMODULARIZE=1 -sEXPORT_NAME=createMain` gives a module to
  instantiate yourself.
- `--preload` moves the bytecode to a separate `main.data`, loaded next to
  the page (under node, relative to the current directory).

### raylib in a browser

A game using [raylib-ocaml](https://github.com/tjammer/raylib-ocaml) builds
as is, with the usual loop:

```ocaml
let () =
  Raylib.init_window 800 450 "game";
  Raylib.set_target_fps 60;
  while not (Raylib.window_should_close ()) do
    Raylib.begin_drawing ();
    Raylib.clear_background Raylib.Color.raywhite;
    Raylib.draw_text "Hello from OCaml" 190 200 20 Raylib.Color.darkgray;
    Raylib.end_drawing ()
  done;
  Raylib.close_window ()
```

```sh
ocaml-emcc build game.html            # emscripten's page, with a canvas
```

The `raylib` recipe builds the raylib that the package vendors for
raylib's `PLATFORM_WEB`: emscripten's GLFW (`-sUSE_GLFW=3`) and WebGL, so
the window is the page's canvas (`Module.canvas` in a page of your own),
and there is no window under node (raylib-ocaml's master after 2.3.0
does it itself for a wasm target, the recipe patches the releases before).
`window_should_close` gives the browser a frame (`emscripten_sleep`),
which the recipe links with `-sASYNCIFY` for. `-- -sJSPI` replaces it with a smaller build (no instrumentation of
the interpreter), for browsers with JSPI. emcc warns that ASYNCIFY is not
compatible with `-fwasm-exceptions`, but OCaml exceptions work, raised from
OCaml or from C, and leaving the loop.

### WASI

```sh
ocaml-emcc build main.wasm --wasi
wasmtime run -W exceptions=y --dir . main.wasm arg1 arg2
```

A `--wasi` module imports only WASI (preview1) functions, and the program sees the arguments, environment, standard
streams, clocks and the directories its host grants it. It is wasm32 only,
as no host runs wasm64 WASI modules.

**Hosts.** The host must implement the standard exception handling
instructions (exnref), which wasmtime 50 and node 22 do: OCaml raises
exceptions from C with `longjmp`, which uses them. wasmtime needs
`-W exceptions=y`, and `--dir DIR` for each directory the program may use.
With node, use `node:wasi` with `version: 'preview1'` and `preopens` (see
`tests/wasi-run.mjs`).

**What works:**

- Files: paths are resolved against the preopened directories, as
  wasi-libc does: `/tmp/x` is `x` in the directory preopened as `/tmp`, and
  a directory preopened as `.` holds every other path. Opening, reading,
  writing, `stat`, directories, renaming, removing, truncating, links and
  times work. `Sys.chdir` and `Sys.getcwd` use a current directory kept by
  the program, `/` at first.
- Waiting: `Unix.sleep` and `Unix.select` wait for the host instead of
  spinning. `Sys.time` is the CPU time of the process, or the time since it
  started when the host has no CPU clock.
- `Unix.dup` and `dup2` of a file the program opened open it again at the
  same position, giving a copy with its own position. This is enough for a
  C library doing `fdopen(dup(fd))`, or to redirect `stdout` to a file. The
  standard streams cannot be duplicated.
- Pipes (`Unix.pipe`) are buffers in memory, between descriptors of the
  program: enough for the wake-up pipes of Async and lwt. Reading an empty
  pipe fails with `EAGAIN` rather than block, as nothing else can fill it,
  unless the program has threads (`--threads`): it then waits for another
  thread to write, as `Unix.select` does.
  Each end takes a descriptor from the host, so a pipe needs a preopened
  directory (`--dir`).

**Sockets.** WASI preview 1 has no call creating a socket. `--wasix` (or
`wasix: yes` in `ocaml-emcc.conf`, for `--wasi`) uses WASIX's, wasmer's
extension of preview 1: `Unix.socket`, `connect`, `bind`, `listen`,
`accept`, `socketpair`, options, addresses, UDP, `getaddrinfo`,
`getnameinfo` (numeric) and `gethostbyname` work, and so do lwt's sockets,
with or without `--threads`. Only wasmer runs such a module:

```sh
ocaml-emcc build server.wasm --wasix
wasmer run --net server.wasm          # --enable-tail-call with --compiled
```

wasmer's `connect` always waits for the connection (its non-blocking one
never completes), and some options of a listening socket cannot be read.
Without `--wasix`, a program can only accept connections on the sockets
its host preopens, the descriptors after the standard streams
(`(Obj.magic 3 : Unix.file_descr)`), with no addresses nor options:
wasmtime 46 does it (`-S preview2=n -S tcplisten=127.0.0.1:8080`), 47
removed it. WASI preview 2's sockets need a component, which emscripten
does not produce.

**What does not:** processes and `Sys.command` fail with `ENOSYS`, and
sockets without `--wasix` (see above). There are no users: everything is owned
by root, and `chmod` and `chown` do nothing. File locks (`fcntl`, `lockf`)
always succeed, as there is a single process. `Unix.localtime` is UTC.

C libraries that call functions emscripten implements in JavaScript (SDL,
the `dlsym` of ctypes-foreign) keep importing them. `link` lists the
imports that are not WASI, and such a module only runs where they are
defined (`wasmtime -W unknown-imports-trap=y` runs it until one is called).

## JavaScript

### js_of_ocaml's library

Programs using [js_of_ocaml](https://ocsigen.org/js_of_ocaml)'s library
(`Js`, `Dom_html`, `Js.Unsafe`, its ppx's `o##m x`, `object%js`...), and
libraries built on it (js_of_ocaml-lwt, [Brr](https://erratique.ch/software/brr)), build
as is, interpreted or compiled, on both targets: ocaml-emcc implements
its primitives (`share/runtime/jsoo.c`, on top of the emscripten library
`jsoo.js`) instead of linking their stubs, which only abort outside
JavaScript.

```ocaml
open Js_of_ocaml

let () =
  let button = Dom_html.createButton Dom_html.document in
  button##.textContent := Js.some (Js.string "click");
  button##.onclick := Dom_html.handler (fun _ -> print_endline "clicked"; Js._true);
  Dom.appendChild Dom_html.document##.body button;
  Js.export "add" (Js.wrap_callback (fun a b -> a + b))   (* add(1, 2) in the page *)
```

JavaScript values follow the conventions of wasm_of_ocaml: in a table on
the JavaScript side, a custom block on the OCaml side, released by the GC.
So code written for wasm_of_ocaml works unchanged:

- A JavaScript number that is an integer (31 bits on wasm32, 53 on wasm64)
  is an OCaml `int`, and an `int` given to JavaScript is a number. Other
  numbers are JavaScript values: use `Js.float_of_number`/`Js.number_of_float`
  (an OCaml float given to JavaScript is a number too).
- Strings are converted (`Js.string`, `Js.to_string`), in UTF-8.
- Any other OCaml value given to JavaScript is an opaque object, and comes
  back as the same OCaml value.
- `Js.wrap_callback` and the other callbacks make JavaScript functions.
  Once the main program is done, the program keeps running them (event
  handlers, timers, promises), as with js_of_ocaml. Under node, the
  process then ends when nothing is left to run. `exit` in a callback ends
  it.
- A JavaScript exception is `Js_error.Exn` in OCaml when it is an `Error`,
  else `Failure`. An OCaml exception crossing JavaScript (raised in a
  callback) comes back as itself.
- `Js.export` sets a global of the page (`module.exports` under node).
- `Js.Unsafe.js_expr` and the like evaluate their string when called, in
  the global scope.
- `Sys_js.set_channel_flusher` and `set_channel_filler` redirect a channel
  to an OCaml function (`stdout` to the page, for instance), and
  `Sys_js.mount` gives the files under a path on demand, in emscripten's
  file system (`create_file` and `read_file` use it too).

The differences with js_of_ocaml:

- Each call goes from wasm to JavaScript and back: 0.1 to 0.5 µs.
- `==` between two JavaScript values is physical equality of the OCaml
  blocks, false for two handles on the same object: use `Js.equals` or
  `Js.strict_equals` (as `Js.Opt` does).
- Typed arrays and bigarrays (`Typed_array`) are copied, not shared: the
  wasm memory can move when it grows.
- An exception raised by the function of a `Sys_js` channel or mount point
  does not reach the program: the function is called from a system call,
  which fails (`Sys_error`), and the exception is printed on the console.
  `Sys_js.mount_point` only lists the paths mounted by the program.

### Primitives in JavaScript

The primitives of a program can be written in JavaScript, in files
given with `--js-file FILE` or listed in `js-files:` in
[`ocaml-emcc.conf`](#configuration) (`tests/jsprims`). Each `function NAME`
of the file, or name declared by a `//Provides: NAME` comment as in
js_of_ocaml's runtime files, implements the primitive `NAME`, which no
library defines. Its arguments and result are JavaScript values as above.
Values the file declares are `Js.Unsafe.runtime_value "NAME"`.

```js
// prims.js
function my_greet(s) { return "hello " + s; }
```

```ocaml
external greet : Js.js_string Js.t -> Js.js_string Js.t = "my_greet"
```

ocamlc checks that the primitives of an executable exist: link it with
`-no-check-prims` (`(link_flags (-no-check-prims))` with dune), as for
js_of_ocaml. Primitives can also be written in C and linked with `-l`.
These files use the conventions above, not those of js_of_ocaml's runtime
(whose strings are not JavaScript strings, among other differences): the
JavaScript files of js_of_ocaml libraries are not linked.

## wasm32 or wasm64

The bytecode is always the one of your switch, compiled for 64 bits. The
target is what the runtime and the C code are compiled for:

- **wasm32** (default): smaller, faster, supported everywhere, but OCaml
  ints are 31 bits at run time (see below).
- **wasm64** (`--target wasm64`): memory64, exactly the semantics of the
  native 64-bit program. Needs node 24 or later (the one shipped with emsdk
  works), Chrome 133 or Firefox 134, and has no WASI.

On wasm32, as with a 32-bit OCaml:

- Integer literals beyond 31 bits (`0x40000000`, `123456789012`) are
  wrapped when the program starts: `0x40000000` becomes `min_int`. This is
  right for code that picks 32-bit variants with `Sys.word_size` (optint,
  used by checkseum and decompress), wrong otherwise. `build`, `link` and
  `doctor` **warn** when there are any (the check is exact). Marshalled
  data holding such integers fails to load
  (`input_value: integer too large`).
- Arithmetic beyond 31 bits wraps silently (`1 lsl 40` is 256).

Packages that require 63-bit ints (`assert (Sys.int_size >= 62)` in matrix,
hence k7 and kaun-board; binsec's marshalled data) need wasm64: matrix, k7,
kaun-board and binsec run there.  So does frama-c (`assert (Sys.word_size =
64)` in unionFind; with `--node-fs`, for its share directory), interpreted
or compiled (c_of_ocaml peaks at about 2 GB on it).

Jane Street's libraries choose some of their code with the configuration
of jst-config, computed on the 64-bit host. On wasm32, `build` and `link`
rebuild jst-config and those of the program's libraries that read its
configuration, or were compiled against one whose interface differs
(core, and with it the async stack), for the target, as for ctypes (see
[internals](docs/internals.md#jane-streets-configuration)): the first
build of an async program takes some tens of minutes. core and async then
run on wasm32, interpreted or compiled, in node and with `--wasi`. Without
threads, the jobs of Async's thread pool (`In_thread.run`: file I/O...)
run synchronously.

## Compiled mode

By default, ocaml-emcc runs the bytecode on an interpreter. With
`--compiled` (for `build` and `link`), it compiles the bytecode to C
instead, with [c_of_ocaml](https://github.com/rboudrouss/C_of_ocaml), a
fork of js_of_ocaml. emcc then compiles this C code
and links it with the usual runtime, minus its interpreter, and the usual
stub libraries:

```sh
ocaml-emcc build main.js --compiled    # c_of_ocaml in PATH, or $OCAML_EMCC_C_OF_OCAML
```

This mode works with OCaml 4.14 and 5, on wasm32 and wasm64. It is still
experimental, but it is usually worth it. Programs run 2 to 5 times faster
in node, and up to 19 times faster on floating-point code such as nbody.
Their `.wasm` is 2 to 8 times smaller, since it contains neither the
interpreter nor the bytecode. There is little to gain when the program
spends its time in C stubs, such as digestif's hash functions. Linking
takes about 1.5 times longer, to compile the generated C.

Limitations:

- **Stack depth.** The compiled code runs on the stack of the wasm engine,
  whereas the interpreter has a stack of its own. Under node, the program
  therefore runs in a worker thread with a stack of `$OCAML_EMCC_STACK_MB`
  megabytes, 1024 by default, which allows millions of nested calls (`0`
  keeps it on the main thread and saves about 40 ms at startup). Running
  out of it is an uncaught `Stack_overflow`. In browsers, the limit is some
  tens of thousands of nested calls.
- **Asyncify.** Tail calls rely on those of WebAssembly, which asyncify
  does not support: with `-sASYNCIFY`, as the raylib recipe links, they
  become ordinary calls, and a long loop of mutually recursive functions
  may run out of stack. If you run into this, link with JSPI instead
  (`-- -sJSPI`, see [raylib in a browser](#raylib-in-a-browser)), which
  keeps tail calls and gives a smaller build, but needs a browser that
  supports it, or node 24 with `--experimental-wasm-jspi`.
- **Effects** cannot be performed across a callback from C: they raise
  `Effect.Unhandled`, as with js_of_ocaml.
- **`Marshal.Closures`** is not supported.
- **Backtraces** work (bytecode compiled with `-g`, as dune does), but
  `Printexc.get_callstack` returns an empty call stack.

### Plugins

A compiled program can load plugins while it runs: parts of it compiled
apart, which a web page fetches only when they are needed. The program
uses the library `ocaml-emcc.dynlink` (module `Emcc_dynlink`), and its
bytecode is linked with `-linkall` (`(link_flags (-linkall))`), since a
plugin may use any module of it (`tests/dynlink`, `tests/dynweb`):

```ocaml
(* in the program *)
let () =
  Emcc_dynlink.load_url "editor.wasm" (function
    | Ok () -> print_endline "the editor is loaded"
    | Error e -> prerr_endline (Printexc.to_string e))
```

```sh
ocaml-emcc build app.js --compiled --dynlink     # or link app.bc ... --compiled --dynlink
ocaml-emcc plugin editor.cma -o editor.wasm --main app.js
```

(Effect handlers need `--effects double-translation` for the program, see
below.)

- `ocaml-emcc plugin` compiles a `.cma` or `.cmo` to a wasm side module
  that emscripten's dynamic linker loads. `--main` checks that the program
  exports everything the plugin needs.
- `Emcc_dynlink.load_url` fetches a plugin, loads it and runs the
  initialization of its modules. `Emcc_dynlink.loadfile` does the same from a
  file of the program (under node, or with emscripten's file system). They
  fail on a plugin that uses a module that is not loaded yet, defines one
  already loaded, or was compiled against another version of the
  interface of a loaded module, as `Dynlink` does. A plugin can use the
  modules of the plugins loaded before it.
- `--dynlink` links the program as an emscripten main module. It exports
  the C symbols plugins import: the runtime, and the stubs and C
  libraries the program links. Its compilation units are kept whole and
  registered by name. This makes the program bigger: 1.2 MB for
  `tests/dynlink`, with the whole standard library.

Limitations:

- The C stubs a plugin needs must be in the program, which links them
  when it uses their library (with `-linkall`, all of its modules).
- Plugins cannot be unloaded.
- Effect handlers (OCaml 5) are disabled by default in a program with
  plugins and in its plugins. `--effects double-translation` enables them
  (`tests/dyneffects`), and a plugin built with `--main` follows the
  program. An effect can then be performed by a plugin under a handler of
  the program, and the other way round. The choice is made when the
  program is built: its plugins may perform effects through any of its
  functions (`List.iter`...), which must then have their CPS version,
  and the program's own code cannot tell, since `-linkall` keeps
  `Stdlib.Effect` (and every other module) whole. That doubles the size of
  the program (1.4 to 2.8 MB for `tests/dynlink`), though its speed
  hardly changes. A plugin built in the other mode is refused when loaded.
- Compiled mode only, without asyncify (the plugin is compiled with tail
  calls).

## Threads

```sh
ocaml-emcc build main.js --threads
ocaml-emcc build main.wasm --wasi --threads
wasmer run main.wasm                # or wasmtime <= 46:
wasmtime run -W exceptions=y,threads=y,shared-memory=y -S threads=y --dir . main.wasm
```

With `--threads` (or `threads: yes` in `ocaml-emcc.conf`), `Thread.create`
starts a real thread, and so does `Domain.spawn` with OCaml 5.3 or later:
domains run in parallel. `Mutex`, `Condition`, `Event`, `Atomic` and
`Domain.DLS` work as natively, interpreted or compiled (`--compiled`: the
generated code then polls, in its loops and before its tail calls, so that
a thread computing lets the others run).

- **node and browsers**: threads are web workers sharing the memory of the
  program (emscripten's pthreads), and so is the program's main thread
  (`-sPROXY_TO_PTHREAD`): the JavaScript thread stays free to run what the
  others ask it (emscripten's file system is there) and to start their
  workers. In a browser, the page must be cross-origin isolated, served
  with the headers `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` (SharedArrayBuffer).
  Programs using js_of_ocaml's primitives keep their main thread on the
  page's, for the DOM: there, workers are started before the program (8,
  OCaml's tick thread included, `-sPTHREAD_POOL_SIZE=N` sets it), as a
  browser only starts a new one once that thread is back in its event
  loop, so a program waiting for more threads than that at once blocks
  forever; that thread waits by spinning, and only runs the other threads'
  file operations when it waits. In compiled mode under node, every thread
  gets the large stack of the main one (`$OCAML_EMCC_STACK_MB`).
- **WASI**: threads use wasi-threads (`thread-spawn`), the ABI of
  wasi-libc's `wasm32-wasip1-threads`: wasmer (7.5; `--volume DIR:/DIR`
  for files) and wasmtime up to 46 (`-S threads=y`; 47 removed it) run
  them. The module imports its memory, shared.
  `Domain.recommended_domain_count` is `$OCAML_EMCC_CPUS`, or 4.
- The runtime reserves the minor heaps of the possible domains at startup:
  8 by default (32 MB on wasm32, 16 MB on wasm64), `OCAMLRUNPARAM=d=N`
  sets it.

lwt runs its blocking jobs (`Lwt_unix` file operations...) in its pool of
threads, and `Lwt_preemptive` works. Async only runs the jobs of its thread
pool (`In_thread.run`) synchronously when it cannot start a thread (not
tried with `--threads` yet).

Without `--threads`, a program is single-threaded as before:
`Thread.create` and `Domain.spawn` fail, while `Mutex` and `Condition` work.
lwt and Async then run their jobs synchronously (`Lwt_preemptive` fails).
The C code is compiled for threads either way (`-pthread`), with no
measurable cost.

## Differences from native

Besides 31-bit integers on wasm32:

- **Threads** need `--threads` (see [Threads](#threads)).
- **ctypes structs**: ctypes and the packages using it are rebuilt for the
  target, so that their structs have its layouts (see
  [ctypes layouts](docs/internals.md#ctypes-layouts)). Those that cannot be
  (packages built without dune) keep the layouts of the 64-bit host, wrong
  on wasm32 for `long`, `size_t` and pointers, and on both targets for the
  structs of the libc (`struct stat`). `build`, `link` and `doctor` **warn**.
- **ctypes-foreign** only finds the C symbols named by string literals of
  the program, not names computed at run time. `dlopen` accepts any file
  name, since everything is linked in.
- **Missing primitives.** A primitive that no linked library defines (a
  stub written for one OS only: Linux's epoll, Windows...) becomes a stub
  raising `Failure "NAME not implemented"` when called, as with
  js_of_ocaml: `link` warns, and a program that never calls it runs.
  `--no-missing-primitives` makes it a link error instead.
- **C type mismatches.** A C function declared by a stub with other types
  than its definition (`int` for `long`) becomes a trap on wasm64. `link`
  warns about each one.
- **Floating-point rounding modes** do not exist in wasm: only
  round-to-nearest is available, so code that switches to directed rounding
  (`fesetround`) loses that guarantee.

## C dependencies

### What is built automatically

Most programs need no configuration. `build` and `link` find the C a
program needs from its bytecode and its opam packages:

- **Stub libraries of opam packages** are
  rebuilt with emcc from the package that installed them: with the builtin
  recipe of that package if there is one, else with the package's own dune
  rules, else from the C files of its native build. Those built with dune
  or from the native build are built again when the package changes
  version, and when ocaml-emcc's toolchain wrappers change.
- **System C libraries**: when a package depends on `conf-gmp`,
  `conf-zlib`..., the recipe of the same name is built and linked. So is
  any recipe providing a `libX.a` for a `-lX` that the package's `.cma`
  files record.
- **`c_library_flags`**: the `-lX` that libraries record for their stubs
  (`(c_library_flags (-lfoo))`, `-cclib -lfoo`) are linked when a wasm
  `libX.a` exists or can be built. Host flags (`-L/usr/lib`, `-Wl,-rpath`)
  and the libraries emcc provides (`-lm`, `-lpthread`...) are dropped, and
  `-lstdc++` links the program as C++.
- **Packages configured on the host**: dune rules that run `pkg-config` or
  `llvm-config` get the answers of the sysroot, and the recipes of the
  libraries a package names are built before its stubs. A package whose
  stubs use mpfr through `pkg-config` (`tests/depgraph`), or a C parser
  built against the host's LLVM (rebuilt against the `clang` recipe), work
  this way.
- **ctypes**: bindings using stub generation (`Cstubs`, dune's `(ctypes)`
  stanza) and ctypes-foreign work on both targets.

A recipe is built once per switch and target, and is not rebuilt when it changes
(ocaml-emcc says so): `ocaml-emcc install --force NAME` rebuilds it.

### Builtin recipes

| recipe | for (opam) | notes |
|--------|------------|-------|
| `gmp`, `mpfr` | zarith, mlmpfr, mlgmpidl, apron, class_group_vdf (gmpxx)... | gmp with its C++ interface |
| `zlib` | camlzip, zlib | |
| `sqlite3` | sqlite3 | amalgamation, single-threaded, FTS3/4/5, R-tree, math functions (`SQLITE_CFLAGS`) |
| `libffi` | ctypes-foreign | |
| `libbz2` | bz2 | |
| `libpcre2-8` | pcre2 | no JIT |
| `zstd` | zstd | single-threaded |
| `gsl` | gsl | with its CBLAS |
| `liblz4` | lz4 | |
| `snappy` | snappy | C++ |
| `expat` | ocaml-expat | |
| `fftw3` | fftw3 | double and single precision, no threads or SIMD |
| `glpk` | glpk | |
| `libargon2` | argon2 | reference implementation, no threads |
| `liblmdb` | lmdb | `MDB_NOLOCK \| MDB_WRITEMAP`: emscripten has no process-shared mutexes, and its file mappings are copies |
| `sdl2` | tsdl | emscripten's port (`-sUSE_SDL=2`); under node, only the timer and events subsystems |
| `glfw3` | glfw-ocaml | emscripten's (`-sUSE_GLFW=3`), WebGL 2; no gamepads; a window needs a web page |
| `libev` | lwt (when the host's uses it) | poll backend |
| `libssl` | ssl | OpenSSL: generic C |
| `ffmpeg` | ffmpeg-avutil, ffmpeg-avcodec... | its own codecs, formats and filters; generic C, no threads, networking or external libraries |
| `cairo` (`pixman`, `libpng`, `freetype`, `libfontconfig`) | cairo2 | image, PDF, PostScript, SVG and script surfaces, FreeType fonts; fontconfig finds the host's fonts under node; no X11; pixman without SIMD; built with meson (and gperf) |
| `oniguruma` | oniguruma | |
| `secp256k1` | secp256k1 | recovery, ECDH, extrakeys, schnorrsig, ellswift and musig modules; the host's minor version |
| `libogg`, `libopus` | ogg, opus | opus without intrinsics |
| `mad` | mad | 64-bit fixed point, no assembly |
| `faad` | faad | |
| `shine` | shine | |
| `ncurses` | curses | wide-character libraries; reads the host's terminfo under node; needs more than 64 KB of stack |
| `libjpeg`, `gd` | gd | libjpeg-turbo without SIMD; libgd with PNG, JPEG and FreeType |
| `liblo` | lo | Open Sound Control (its server thread needs `--threads`) |
| `openblas` | lacaml, nx, owl... (`-lblas`, `-llapack` too) | BLAS, CBLAS, LAPACK and LAPACKE in C (no Fortran), generic kernels, no threads; its subroutines' C signatures made to agree (wasm traps on a mismatch); 30 to 40 minutes to build on one core |
| `lame` | lame | libmp3lame, no assembly |
| `libevent` | libevent | poll and select backends, no OpenSSL |
| `liblzo2` | lzo | |
| `nlopt` | nlopt | its C algorithms (not StoGO or AGS, in C++) |
| `frei0r` | frei0r | its header only: no plugins |
| `clang` | programs embedding clang's frontend | see [docs/recipes.md](docs/recipes.md#the-clang-recipe) |

These recipes take the sources of the opam package
that vendors the library if the switch has it, else
the newest upstream release compatible with the host's library (see
[system recipes](docs/recipes.md#system-recipes)).

OCaml packages, built from the sources of the installed package:
`zarith`, `camlidl`, `mlgmpidl`, `apron` (every domain and numeric
variant), `mlcuddidl` (its bundled CUDD, and the stubs camlidl generates),
`hacl-star-raw` (portable C only: the vectorized and Vale variants trap if
called), and packages whose sources need a change for wasm, described in
their `share/recipes/<name>/` directory: `mirage-crypto` (and `-ec`,
`-rng`), `lwt`, `cryptokit`, `secp256k1-internal`, `lmdb`, `mccs`,
`core_unix`, `async_unix`, `eio_posix`, `num`, `rowex`, `mirage-block-unix`, `miou`, `osdp`, `bls12-381-unix`, `lacaml`, `setcore`, `cpu`, `memcpy`, `scrypt`, `poll`, `bytesrw`, `class_group_vdf`, `ocaml-lua` and `raylib` (see [raylib in a
browser](#raylib-in-a-browser)).

### Project recipes

A project recipe lives in `emcc-recipes/<name>/recipe.sh` next to
`dune-project`, is listed in `requires:` and linked with `link-flags:` in
[`ocaml-emcc.conf`](#configuration). This one clones cJSON
(`tests/gitrecipe`):

```sh
# emcc-recipes/cjson/recipe.sh
SOURCE=git:https://github.com/DaveGamble/cJSON.git
REF=v1.7.18                       # tag, branch or commit

build() {                         # runs in a fresh copy of the sources
  "$EMCC" $CFLAGS -c cJSON.c -o cJSON.o
  mklib cjson cJSON.o             # -> libcjson.a
  install_lib libcjson.a
  install_headers cjson cJSON.h   # -> #include <cjson/cJSON.h>
}
```

Project recipes take precedence over the builtin ones (`share/recipes/`).
More directories can be added with `--recipes DIR` or
`$OCAML_EMCC_RECIPES_PATH`.

A project recipe can also **refine** a builtin one: `include_recipe NAME`
reads the next recipe of that name, after the project's variables are set,
and an optional `pre_build` function runs before its `build`, to patch the
sources. [MOPSA](https://github.com/rboudrouss/mopsa-emcc/tree/ocaml-emcc) pins clang 9 and patches apron this way:

```sh
# emcc-recipes/clang/recipe.sh
LLVM_VERSION=9.0.1
include_recipe clang

# emcc-recipes/apron/recipe.sh
include_recipe apron
pre_build() { sed -i '...' apron/ap_manager.c; }
```

Recipes for system C libraries, the variables, functions and helpers
recipes can use, and how their patches are applied are described in
[docs/recipes.md](docs/recipes.md).

## Configuration

A project can have an `ocaml-emcc.conf`, looked up from the current
directory upwards. Every field is optional:

```
target: wasm32                  # default target of the project
requires: cjson                 # recipes built before building/linking
link-flags: -lcjson -sINITIAL_MEMORY=64MB
cflags: -DNDEBUG
recipes: emcc-recipes           # recipe directories (default: ./emcc-recipes)
threads: yes                    # link with --threads
wasix: yes                      # --wasi links with --wasix (sockets)
```

Emscripten link flags come from, in increasing precedence (emcc keeps the
last `-s` setting): `link-flags:`, `$OCAML_EMCC_LDFLAGS`, `--emcc-flag F`,
then the arguments after `--`:

```sh
ocaml-emcc build app.js -- --preload-file assets@/assets \
  -sINITIAL_MEMORY=128MB -sENVIRONMENT=web
```

C flags for stubs and recipes come from `cflags:` and
`$OCAML_EMCC_EXTRA_CFLAGS`.

## Without dune

`build` chains the following commands, which can also be run on their own
from scripts and Makefiles:

```sh
ocaml-emcc setup                         # wasm runtime of the switch (once per target)
ocaml-emcc install gmp zarith cjson      # build recipes
ocaml-emcc dune ./bin/main.bc            # dune build -x wasm32: C stubs compiled with emcc
ocaml-emcc doctor prog.bc                # how stubs and primitives resolve, 31-bit literals
ocaml-emcc deps prog.bc                  # build the missing stub libraries of prog.bc
ocaml-emcc link prog.bc -o prog.js       # the final link
ocaml-emcc env --cflags                  # flags to compile C stubs yourself
```

Without dune, build the bytecode however you like, compile your stubs with
`emcc $(ocaml-emcc env --cflags)` and give their archive to `link`. The
stub libraries of your dependencies are found from the bytecode itself
(`tests/nodune/Makefile`):

```make
out/prog.js: prog.bc libstub.a
	ocaml-emcc link prog.bc -o $@ -l ./libstub.a

libstub.a: stub.c
	emcc $$(ocaml-emcc env --cflags) -c stub.c -o stub.o
	emar rcs $@ stub.o

prog.bc: prog.ml      # -no-check-prims: our primitives only exist in libstub.a
	ocamlfind ocamlc -package zarith,unix -linkpkg -no-check-prims prog.ml -o $@
```

A bytecode that uses ctypes should be compiled against the packages
rebuilt for the target (`link` warns otherwise):
`OCAMLFIND_CONF=<sysroot>/findlib.conf ocamlfind -toolchain wasm32 ocamlc ...`
(or `-toolchain wasm64`).

## How it works

The bytecode is compiled by the switch's own `ocamlc`, and runs on an
`ocamlrun` that emcc builds from the sources of the switch's compiler. The
C stubs of the program and of its dependencies are rebuilt with emcc and
linked with the runtime and the bytecode into one module.
[docs/internals.md](docs/internals.md) details each step, standalone and
WASI modules, ctypes, the flags used for all C code and the workarounds
for each OCaml version.

## Status

The test suite ([tests/README.md](tests/README.md)) builds about 40
programs with C stubs (zarith, apron, sqlite3, ctypes, lwt, mirage-crypto,
hacl-star, mccs, sdl...) and compares their output under node with that
of the native executable. It passes on both targets, except `ctypes` on
wasm64 (libffi's calls stop on "Unexpected type 0" with emsdk 6.0.11). For
0.3.0 it passed on every OCaml version from 4.08 to 5.5, and its WASI
part with wasmtime 50. CI runs it on OCaml 4.14 and 5.5. In compiled mode
(`tests/run.sh --compiled`), it passes on OCaml 4.14 (wasm32) and 5.4
(wasm32 and wasm64).

### Versions of the dependencies

`tests/versions.sh` installs each version of a package in turn (opam takes
its dependents along), runs the tests about it, and puts the packages of
the switch back. On wasm32, OCaml 4.14.2:

| tests | package | versions that pass | others |
|-------|---------|--------------------|--------|
| `zarith` | zarith | 1.11, 1.12, 1.13, 1.14 | |
| `mixed` | digestif | 1.1.2, 1.3.0, 1.4.1 | |
| `sqlite` | sqlite3 | 5.0.3, 5.2.0, 5.4.2 | |
| `zstd` | zstd | 0.4 | 0.3: the test uses later functions |
| `gsl` | gsl | 1.24.3, 1.25.1 | 1.22.0: not installable on OCaml 4.14 |
| `camlzip` | camlzip | 1.11, 1.13, 1.14 | |
| `ctypes`, `cstanza` | ctypes, ctypes-foreign | 0.21.1, 0.22.0, 0.23.0, 0.24.0 | 0.20.2, built by make, cannot be rebuilt for wasm32: its layouts are the host's (`link` warns) |
| `yaml` | yaml | 3.0.1, 3.1.0, 3.2.0 | |
| `mcrypto` | mirage-crypto | 2.4.1 | 2.0.2, 2.2.0: the test uses later functions |
| `lwt` | lwt | 5.6.1, 5.9.2, 6.1.2 | |
| `cryptokit` | cryptokit | 1.21.1 | 1.20: the test uses later functions |
| `secp` | secp256k1-internal | 0.3.1, 0.4.0 | |
| `apron` | apron | v0.9.14, v0.9.15 | v0.9.13: does not build natively (GCC 14) |
| `extunix` | extunix | 0.4.4 | 0.3.2, 0.4.1: `splice.c` returns a `value *` as an `off_t *`, an error on 32-bit targets |
| `stb` | stb_image | 0.4, 0.5 | |
| `minisat` | minisat | 0.4, 0.6 | |
| `cudd` | mlcuddidl | 3.0.8 | 3.0.6, 3.0.7: do not build natively (GCC 14) |
| `hacl` | hacl-star | 0.7.2 | 0.5.0, 0.6.2: the test uses later modules (`K256`) |
| `posix` | posix-time2, -socket, -stat | 4.0.2 | 2.2.0, 3.0.0: no posix-stat |
| `mccs` | mccs | 1.1+13, 1.1+17, 1.1+19 | |
| `raylib` | raylib | 2.2.2, 2.3.0, master (bd831de) | |

The recipes' patches (placed by their text, see [patches](docs/recipes.md#patches)) were
also checked to apply, as GNU patch applied the previous ones, to the
sources of every OCaml version from 4.08 to 5.5 and of lwt 5.4 to 6.1,
mirage-crypto 0.11 to 2.4, cryptokit 1.16 to 1.21, secp256k1-internal 0.3
and 0.4, lmdb 1.1, dune 3.12 to 3.24 and mccs 1.1+13 to 1.1+19.

## Next steps

- Propose the patch of dune's `(ctypes)` stanza upstream
  ([ocaml/dune#13650](https://github.com/ocaml/dune/issues/13650)), so that
  the switch's dune can build it.
- More recipes: ppl (C++, apron's `ppl` and `polkaGrid` domains), flint,
  libtidy, and newer LLVM versions for `clang`.
- WASI: a `dlsym` that needs no JavaScript (a table of the exported
  functions generated by `link`), though ctypes-foreign would still need a
  libffi without JavaScript. WASI preview 2 (components, its sockets) is
  not targeted.

## License

ocaml-emcc is distributed under the MIT license (`LICENSE`), except
`share/runtime/jsoo.js`, the JavaScript side of js_of_ocaml's primitives,
parts of which are adapted from js_of_ocaml's runtime. It is distributed
under js_of_ocaml's license: the GNU LGPL version 2.1 or later, with a
linking exception (`share/runtime/jsoo.js.LICENSE`). The exception lets a
program linked with it be distributed under any terms.

## Development

```
bin/main.ml           CLI
src/util/             generic helpers: stdlib compat, strings, files, ar archives
src/env/              switch, sysroot, ocaml-emcc.conf, emcc flags, toolchain wrappers
src/recipes/          recipes: what to build (stamps), their sources, running driver.sh
src/packages/         opam packages for the target: C stubs, ctypes builds, missing libs
src/link/             bytecode reading, dune executables, the final link
share/driver.sh       recipe driver: reads a recipe, runs its build function
share/recipes/        ocaml (runtime + patches), C libraries (gmp, mpfr, zlib...),
                      OCaml packages needing changes (zarith, apron, lwt...)
share/tools/          ocamlc / ocamlmklib wrappers for dune -x, dune's (ctypes) patch
share/runtime/        main.c, compat.c, dlsym.c, wasi.c, node_stdio.js, node_stack.js
test/                 unit tests (dune test)
tests/                test suite (tests/README.md)
docs/                 internals, recipe authoring
```
