# ocaml-emcc

Compile OCaml programs **together with their C stubs** to WebAssembly, for
node, browsers and WASI hosts.

Your program and its dependencies (zarith/gmp, unix, str, digestif, your own
`foreign_stubs`, a C library cloned from GitHub...) end up in one
emscripten module. Unlike js_of_ocaml / wasm_of_ocaml, no C stub has to be
rewritten in JavaScript, so FFI-heavy code works as is.

The OCaml code is compiled to C by
[c_of_ocaml](https://github.com/rboudrouss/C_of_ocaml), a fork of
js_of_ocaml, and emcc compiles it with the stubs. The result runs about
as fast as wasm_of_ocaml's. The bytecode can also be run on an
interpreter instead (`--interpreted`), but that mode is slower and less
tested (see
[Compiled or interpreted](#compiled-or-interpreted)).

- [Quick start](#quick-start) · [Requirements](#requirements)
- [What works where](#what-works-where) (outputs, environments)
- [Compiled or interpreted](#compiled-or-interpreted) (the two modes and their limits)
- [Commands and options](#commands-and-options) · [Configuration](#configuration)
- Running in [node](#in-node), [browsers](#in-a-browser), [raylib](#raylib-in-a-browser), [WASI](#wasi)
- [JavaScript](#javascript) · [wasm32 or wasm64](#wasm32-or-wasm64) · [Plugins](#plugins) · [Threads](#threads)
- [Differences from native](#differences-from-native) · [C dependencies](#c-dependencies) · [Without dune](#without-dune)
- [How it works](#how-it-works) · [Status](#status) · [Development](#development)

## Quick start

```sh
opam install ocaml-emcc             # or opam pin add ocaml-emcc git+https://github.com/rboudrouss/ocaml-emcc.git
source /path/to/emsdk/emsdk_env.sh  # emcc in PATH
export OCAML_EMCC_C_OF_OCAML=/path/to/c_of_ocaml.exe   # or c_of_ocaml in PATH, see below

ocaml-emcc build main.js            # in your dune project
node main.js                        # or load main.js in a web page
```

`ocaml-emcc build main.js` finds the dune executable named `main`, builds a
wasm OCaml runtime from the sources of your switch's compiler (the first
time only), compiles the C stubs of the program and of its dependencies
with emcc, compiles the program to C, and writes `main.js` and
`main.wasm`.

## Requirements

| what | version | notes |
|------|---------|-------|
| opam switch | OCaml 4.14 or later (4.x or 5.x) | interpreted only with 4.08 to 4.13 |
| [emsdk](https://emscripten.org/docs/getting_started/downloads.html) | tested with 6.0.11 | `emcc` in `PATH`, 4.0 or later for standalone `.wasm` outputs |
| c_of_ocaml | its `master` | in `PATH` or `$OCAML_EMCC_C_OF_OCAML`, not needed with `--interpreted` |
| dune | 3.11 or later | except for projects built [without dune](#without-dune) |
| node | the one of emsdk works | to run `.js` outputs, 24 or later for wasm64 |

ocaml-emcc rebuilds the compiler's runtime and the C stubs of the packages
from their sources. They are fetched once with `opam source` (network
access, a version still in the opam repository), unless the switch kept
them (`--keep-build-dir` or `OPAMKEEPBUILDDIR=true` when installing).
Everything it builds (the runtime, C libraries, rebuilt packages) lives in
`$OPAM_SWITCH_PREFIX/emcc-sysroot/` and goes away with the switch.

c_of_ocaml is not in opam, it is installed apart, like emscripten. Build it
in the switch of your project:

```sh
git clone --depth 1 https://github.com/rboudrouss/C_of_ocaml.git && cd C_of_ocaml
opam pin add -n -y ppx_devtools-optcomp.dev "git+https://github.com/ocsigen/ppx_devtools.git#f62719d5087fa8d7f2bd0616c1fa91fd660eb27e"
opam install -y --deps-only ./js_of_ocaml-compiler.opam
dune build --profile release compiler/bin-c_of_ocaml/c_of_ocaml.exe
export OCAML_EMCC_C_OF_OCAML=$PWD/_build/default/compiler/bin-c_of_ocaml/c_of_ocaml.exe
```

## What works where

### Outputs

The extension of the output and `--wasi` decide what is written.

| `ocaml-emcc build ...` | what it is | runs in | run it with |
|------------------------|------------|---------|-------------|
| `main.js` (+ `main.wasm`) | the module and emscripten's JavaScript glue | node, browsers | `node main.js ARGS`, `<script src="main.js">` |
| `main.html` (+ `.js`, `.wasm`) | the same, plus a minimal emscripten page | browsers | open the page (served over HTTP) |
| `main.wasm --wasi` | a module importing only WASI (preview 1) functions | wasmtime, node's `node:wasi`, wasmer | `wasmtime run -W exceptions=y --dir . main.wasm ARGS` |
| `main.wasm --wasix` | `--wasi`, with WASIX's sockets | wasmer | `wasmer run --net main.wasm` |
| `main.wasm` | a standalone module, without JavaScript | hosts providing emscripten's imports | (your host) |

A standalone `.wasm` without `--wasi` still imports emscripten functions
(file operations other than read and write, `getcwd`, sockets...), which
its host has to provide (see [standalone
WebAssembly](https://v8.dev/blog/emscripten-standalone-wasm)). `--wasi`
uses emscripten's experimental `-sPURE_WASI`.

### Environments

C stubs, recipes, the standard library and Unix's computations work the
same in every environment. What the program gets from its environment
differs.

| | node | node, `--node-fs` | browser | WASI (`--wasi`) | WASIX (`--wasix`) |
|-|------|-------------------|---------|-----------------|-------------------|
| arguments, exit code | yes | yes | `Module.arguments` | yes | yes |
| standard streams | bytes (pipes, redirections) | bytes | lines (`Module.print`, `printErr`, `stdin`) | yes | yes |
| files | in memory (emscripten's) | the real ones | in memory | the preopened directories (`--dir`) | the preopened directories |
| `Sys.getenv` | emscripten's defaults | the process's | emscripten's defaults | what the host passes | what the host passes |
| local time zone | the host's | the host's | the browser's | UTC for `Unix.localtime`, `/etc/localtime` for core if preopened | idem |
| sockets | emscripten's emulation, not tested | idem | idem | accept on preopened sockets (wasmtime 46) | yes (TCP, UDP, names) |
| threads (`--threads`) | yes | yes | cross-origin isolated pages | wasmer, wasmtime ≤ 46 | wasmer |
| processes (`Sys.command`, `fork`) | no | no | no | no | no |
| js_of_ocaml's `Js`, the DOM | yes | yes | yes | no | no |
| plugins (`--dynlink`) | yes | yes | yes | no | no |
| wasm64 (`--target wasm64`) | node 24 | node 24 | Chrome 133, Firefox 134 | no host | no host |

## Compiled or interpreted

| | compiled (default) | interpreted (`--interpreted`) |
|-|--------------------|-------------------------------|
| how | c_of_ocaml compiles the bytecode to C, emcc compiles the C | an `ocamlrun` compiled to wasm runs the bytecode |
| OCaml | 4.14 and later | 4.08 and later |
| needs | c_of_ocaml | nothing more |
| speed | at least 5 times faster than interpreted, about as fast as wasm_of_ocaml | about 1.5 times slower than the native `ocamlrun` |
| `.wasm` size | 2 to 8 times smaller (no interpreter, no bytecode) | the interpreter and the bytecode |
| link time | about 1.5 times longer (the generated C is compiled) | |
| tested | the whole test suite, in CI (OCaml 4.14 and 5.5, wasm32, wasm64, WASI) | in CI, threads, sockets and Jane Street's libraries only |
| effect handlers (OCaml 5) | yes (c_of_ocaml's double translation, chosen per program, see `--effects`) | yes |
| plugins | `Emcc_dynlink` (`ocaml-emcc plugin`) | OCaml's `Dynlink`, of bytecode (see [Plugins](#plugins)) |
| threads, domains, js_of_ocaml's library, WASI | yes | yes |
| deep recursion | the engine's stack: 1 GB under node, 500 KB to 1 MB in browsers, without limit with [`--jspi` or `--cps-stack`](#deep-recursion-in-a-browser) | the interpreter's own stack, as natively |
| `Printexc.get_callstack` | empty (backtraces of exceptions work) | yes |
| with asyncify (`-sASYNCIFY`) | without wasm tail calls by default, as `--no-tail-calls` (see below) | yes |
| `--preload` | nothing to preload | the bytecode in a separate `.data` file |


### The compiled mode

- **Speed**: there is little to gain when the program spends its time in
  C stubs (digestif's hash functions...).
- **Small functions**: c_of_ocaml pads the module with small functions
  (a few percent of its size) because V8 cuts the inlining budget of a
  module that has few of them. This only helps V8 (node, Chrome), so
  `--wasi` turns it off (c_of_ocaml's `--disable small-functions`).
- **Stack depth**: the compiled code runs on the stack of the wasm engine.
  Under node, the program therefore runs in a worker thread with a stack
  of `$OCAML_EMCC_STACK_MB` megabytes, 1024 by default (`0` keeps it on
  the main thread and saves about 40 ms at startup). Running out of it is
  an uncaught `Stack_overflow`. For browsers, see [Deep recursion in a
  browser](#deep-recursion-in-a-browser).
- **Tail calls**: OCaml's tail calls are WebAssembly tail calls
  (`return_call`, emcc's `-mtail-call`), so that mutually recursive
  functions loop in constant stack, as natively. Engines have them since
  Chrome 112, Firefox 121, Safari 18.2 and node 20 (wasmer with
  `--enable-tail-call`), and older ones do not load the module. They do
  not change the speed: without them the Ocsigen benchmarks run as fast,
  `--cps-stack` too.
- **`--no-tail-calls`** (`tail-calls: no`) compiles without them, and is
  only for the older browsers that lack them (Safari before 18.2, Firefox
  before 121, Chrome before 112). Tail calls then become ordinary calls,
  so a long loop of tail calls (mutually recursive functions, a loop
  through closures) may overflow the stack. Those browsers have no JSPI
  either, and a stack of 500 KB to 1 MB: a program recursing deeply will
  probably need `--cps-stack` too (see [Deep recursion in a
  browser](#deep-recursion-in-a-browser)). The plugins of such a program
  follow it (`plugin --main`, or `plugin --no-tail-calls`).
- **Asyncify**: Asyncify do not support WebAssembly tail calls.
  With `-sASYNCIFY`, as the raylib recipe links, ocaml-emcc turns them
  off by default, as `--no-tail-calls` does: they become ordinary calls,
  so a long chain of mutually recursive tail calls may overflow. You might need to use `--cps-stack` (or `--jspi` instead of Asyncify), see [Deep recursion in a
  browser](#deep-recursion-in-a-browser).
- **Effects** performed across a callback from C raise
  `Effect.Unhandled`.
- **Backtraces** work when the bytecode is compiled with `-g`, as dune
  does.

## Commands and options

`build` does everything for a dune project. The other commands are its
steps, for scripts and Makefiles (see [Without dune](#without-dune)).
`ocaml-emcc help` prints the same.

| command | what it does |
|---------|--------------|
| `build OUT [--exe DIR/NAME] [LINK OPTIONS] [-- EMCC-ARGS]` | the dune executable named like `OUT` (or `--exe`), its C stubs and those of its dependencies, the link |
| `link PROG.bc -o OUT [LINK OPTIONS] [-- EMCC-ARGS]` | the link of a bytecode executable built otherwise |
| `plugin LIB.cma\|M.cmo -o OUT.wasm [--main PROG.js] [--effects MODE] [--cps-stack] [--threads] [--no-tail-calls] [-O FLAG]` | a [plugin](#plugins), compiled and linked as the program with `--main` (effects, `--cps-stack`, threads, tail calls), which also checks that the program exports what it needs |
| `plugin --interpreted LIB.cma [-o DIR] [--main PROG.js]` | the C stubs of a bytecode plugin, `DIR/dllX.so` in wasm, for an interpreted program's `Dynlink` (implied by `--main` when the program is interpreted) |
| `setup [--force]` | the wasm runtime of the switch's compiler (`build` and `link` do it the first time) |
| `install [--force] RECIPE...` | build [recipes](#c-dependencies) (gmp, project recipes...), again with `--force` |
| `dune [ARGS]` | `dune build -x TARGET ARGS` (the C stubs compiled with emcc), and their static archives |
| `deps PROG.bc [-L DIR]` | build the missing stub libraries of `PROG.bc` |
| `doctor PROG.bc [-L DIR]` | how its stub libraries and primitives resolve, its 31-bit literals, its packages rebuilt for the target |
| `env [--cflags\|--sysroot]` | paths and configuration, or with `--cflags` the flags to compile C stubs with emcc |

`build` builds the executable at the same path as the output (`bin/main.js`
→ `bin/main`), else the only executable of the project with that name, or
the one `--exe DIR/NAME` names. Any `(modes ...)` works, `byte` is not
needed.

**Link options** (`build` and `link`):

| option | what it does | when to use it |
|--------|--------------|----------------|
| `--interpreted` | runs the bytecode on the interpreter | see [Compiled or interpreted](#compiled-or-interpreted) |
| `--compiled` | the default | accepted for older scripts |
| `--effects MODE` | effect handlers of the compiled code, `double-translation` or `disabled` | the default (double translation when the program's code performs effects, or with `--cps-stack`) is right unless plugins perform effects through a program performing none, see [Plugins](#plugins) |
| `--threads` | `Thread.create` and `Domain.spawn` start real threads | a program with threads or domains, see [Threads](#threads) |
| `--dynlink` | a program loading plugins (implied when it links `Emcc_dynlink`) | see [Plugins](#plugins) |
| `--jspi` | links with JSPI (`-sJSPI`), with an asynchronous `main` and, compiled, deep recursions on new stacks | deep recursion in browsers that have JSPI, or instead of `-sASYNCIFY`, see [Deep recursion in a browser](#deep-recursion-in-a-browser) |
| `--cps-stack` | compiled, deep recursions go on in CPS on the heap (a bigger program) | deep recursion in every browser, see [Deep recursion in a browser](#deep-recursion-in-a-browser) |
| `--no-tail-calls` | compiled without wasm tail calls (implied by `-sASYNCIFY`) | only for browsers without them (Safari < 18.2, Firefox < 121, Chrome < 112), with `--cps-stack` for deep recursions, see [The compiled mode](#the-compiled-mode) |
| `--wasi` | `OUT.wasm` for a WASI host | see [WASI](#wasi) |
| `--wasix` | `--wasi`, with WASIX's sockets | network programs under wasmer |
| `--node-fs` | the real file system and environment, node only | programs reading files installed with them (dune-site, why3's `share/why3`, frama-c) or the user's files |
| `--preload` | the bytecode in a separate `main.data` (interpreted) | a page loading the bytecode apart |
| `-l LIB`, `-L DIR` | more libraries (`-lfoo`, `libfoo.a`, `x.o`) and where to find them | C of your own, built by hand |
| `--no-deps` | does not build the missing stub libraries | to see what is missing without building |
| `--no-missing-primitives` | a primitive no library defines is a link error | instead of a stub raising `Failure` when called |
| `--js-file F` | primitives written in JavaScript | see [Primitives in JavaScript](#primitives-in-javascript) |
| `-O FLAG` | emcc's optimisation (default `-O2`) | `-Oz` for size, `-O0` to debug |
| `--stack-size S` | the C stack (default `8MB`) | C code with deep recursion or large stack frames |
| `--emcc-flag F`, `-- ARGS` | emcc link flags | `-sINITIAL_MEMORY=...`, `-sMODULARIZE=1`, `--preload-file`... |

**Global options** (before the command):

| option | what it does |
|--------|--------------|
| `--target wasm32\|wasm64` | wasm32 (default) or wasm64, see [wasm32 or wasm64](#wasm32-or-wasm64) |
| `--switch SW` | the opam switch (default: the current one) |
| `--sysroot DIR` | where wasm artifacts go (default `<switch>/emcc-sysroot/<target>`) |
| `--recipes DIR` | another recipe directory (repeatable) |
| `-v` | shows the commands run |

**Environment variables**:

| variable | when | what |
|----------|------|------|
| `OCAML_EMCC_C_OF_OCAML` | build | the c_of_ocaml executable (default: the one in `PATH`) |
| `OCAML_EMCC_TARGET` | build | as `--target` |
| `OCAML_EMCC_SYSROOT` | build | as `--sysroot` |
| `OCAML_EMCC_RECIPES_PATH` | build | more recipe directories (`:`-separated) |
| `OCAML_EMCC_LDFLAGS` | build | more emcc link flags |
| `OCAML_EMCC_EXTRA_CFLAGS` | build | more C flags for the stubs and recipes |
| `OCAML_EMCC_STACK_MB` | run, node, compiled | the stack of the program, in MB (default 1024, `0` for node's main thread) |
| `OCAML_EMCC_STUBLIBS` | run, interpreted, `--dynlink` | the directories (`:`-separated) of the wasm `dllX.so` of bytecode plugins, before the current one |
| `OCAML_EMCC_CPUS` | run, WASI | `Domain.recommended_domain_count` (default 4) |
| `OCAMLRUNPARAM` | run | as natively (`d=N` sets the number of domains), read with `--node-fs` and under WASI only |

## Configuration

A project can have an `ocaml-emcc.conf`, looked up from the current
directory upwards. Every field is optional.

| field | what | example |
|-------|------|---------|
| `target:` | the default target of the project | `target: wasm64` |
| `requires:` | recipes built before building or linking | `requires: cjson` |
| `link-flags:` | emcc link flags | `link-flags: -lcjson -sINITIAL_MEMORY=64MB` |
| `cflags:` | C flags for the stubs and recipes | `cflags: -DNDEBUG` |
| `recipes:` | recipe directories (default: `./emcc-recipes`) | `recipes: emcc-recipes vendor/r` |
| `js-files:` | primitives written in JavaScript | `js-files: js/prims.js` |
| `threads:` | link with `--threads` | `threads: yes` |
| `jspi:` | link with `--jspi` | `jspi: yes` |
| `cps-stack:` | link with `--cps-stack` | `cps-stack: yes` |
| `tail-calls:` | `no`: link with `--no-tail-calls` | `tail-calls: no` |
| `wasix:` | `--wasi` links with `--wasix` | `wasix: yes` |
| `interpreted:` | link with `--interpreted` (`--compiled` overrides it) | `interpreted: yes` |

Emscripten link flags come from `link-flags:`, `$OCAML_EMCC_LDFLAGS`,
`--emcc-flag F`, then the arguments after `--`, in increasing precedence
(emcc keeps the last `-s` setting):

```sh
ocaml-emcc build app.js -- --preload-file assets@/assets \
  -sINITIAL_MEMORY=128MB -sENVIRONMENT=web
```

## Running

### In node

```sh
node main.js arg1 arg2
```

The program behaves like a native executable (`node main.js < in.bin >
out.bin` works), with the files and environment of [the
table](#environments): `--node-fs` gives it the real ones, but then it only
runs in node. Interpreted, its bytecode is embedded in the `.wasm`, or
written next to `main.js` with `--node-fs`.

### In a browser

The same `main.js` and `main.wasm` work in a web page, with the arguments
and the output in the `Module` object:

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

- Don't declare global `out` or `err` variables in the page, emscripten's
  script declares them.
- `Module.print`, `printErr` and `stdin` take precedence over node's
  streams too.
- `-- -sMODULARIZE=1 -sEXPORT_NAME=createMain` gives a module to
  instantiate yourself.

### Deep recursion in a browser

Compiled code recurses on the stack of the wasm engine, which is 984 KB
on the page's thread in Chrome and about 500 KB in a worker, that is
6 000 to 15 000 nested calls of OCaml code. A parser or an analyser
recursing on a large input runs out of it. Two link options let a compiled function about to go
deeper than a limit of the current stack go on elsewhere, so that the
recursion is only limited by memory.

- `--jspi` (`jspi: yes` in `ocaml-emcc.conf`) continues the recursion on
  a new stack of the engine, which JSPI (WebAssembly's JavaScript Promise
  Integration) gives, while the current one waits, suspended (c_of_ocaml's
  segmented stack).
- `--cps-stack` (`cps-stack: yes`) gives the recursive functions a version
  in continuation-passing style, as for effect handlers (double
  translation), and continues the recursion in it, on the heap
  (c_of_ocaml's CPS stack).

```sh
ocaml-emcc build app.js --jspi         # or --cps-stack
```

| | `--jspi` | `--cps-stack` |
|-|----------|---------------|
| browsers | Chrome and Edge 137 and later (Firefox announces it for 153, Safari has it in its preview only) | all |
| `main` | asynchronous | synchronous |
| size of the `.wasm` | about 4 % more | 0 to 10 % more for small numeric programs, about 50 % more with `Printf` or `Format`, twice as much C to compile |
| speed | about 2 % slower on average, up to a third on a plain recursion of integers | about 4 % slower until reaching the limit, then 2 to 3 times slower than with JSPI |
| recursions still limited by the stack | in callbacks from C or JavaScript | in callbacks from C, through functions with unboxed (float) arguments or results, and tree recursions without frames (`fib`) |
| plugins (`--dynlink`) | yes, their code goes on new stacks too | yes, the plugins compiled with `--cps-stack` too (see [Plugins](#plugins)) |
| suspending C (`emscripten_sleep`...) | yes, instead of `-sASYNCIFY` | no, you need to use `-sASYNCIFY` |

**With `--jspi`.**

- A build with `--jspi` does not load without JSPI (the program says so).
  For the other browsers, serve a second build, with `--cps-stack` or
  interpreted (the interpreter has a stack of its own), and choose with
  `typeof WebAssembly.Suspending == "function"`.
- The program runs as an asynchronous function. A page or a worker that
  starts it (`Module.callMain` with `-sINVOKE_RUN=0`, or the module of
  `-sMODULARIZE=1`) gets a promise, to wait for before using its results.
  `exit` still ends it with an `ExitStatus`.
- OCaml code called back from C or JavaScript (an event handler, a
  js_of_ocaml callback) stays on the stack it is called on, as JSPI
  cannot suspend JavaScript frames. A deep recursion has to start from
  the program's main code.
- node needs neither option (a 1 GB stack). node 24 runs a `--jspi` build
  with `node --experimental-wasm-jspi`.
- No `--jspi` for a standalone `.wasm` (`--wasi`), as JSPI works through
  the JavaScript glue.
- `--jspi` takes precedence over `-sASYNCIFY`. The C functions of
  emscripten that suspend (`emscripten_sleep`) work as with asyncify, also
  in C calling OCaml back.

**With `--cps-stack` and `-sASYNCIFY`.** Asyncify compiles without wasm
tail calls, so the returns of the CPS code bounce on c_of_ocaml's
trampoline as well: the recursions stay limited by memory only, and C
suspends under them (`tests/cpsasync`). ocaml-emcc gives asyncify 1 MB
for the stack it saves while C suspends (`-sASYNCIFY_STACK_SIZE`, 4 KB by
default, which some hundred frames of compiled code exceed).

### raylib in a browser

A game using [raylib-ocaml](https://github.com/tjammer/raylib-ocaml) builds
as is, with the usual loop.

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

- The `raylib` recipe builds the raylib that the package vendors for
  raylib's `PLATFORM_WEB`, with emscripten's GLFW (`-sUSE_GLFW=3`) and
  WebGL. The window is the page's canvas (`Module.canvas` in a page of
  your own). There is no window under node.
- `window_should_close` gives the browser a frame (`emscripten_sleep`),
  which the recipe links with `-sASYNCIFY` for, or `--jspi` (see
  [Asyncify](#the-compiled-mode)).
- emcc warns that ASYNCIFY is not compatible with `-fwasm-exceptions`, but
  OCaml exceptions work.

### WASI

```sh
ocaml-emcc build main.wasm --wasi
wasmtime run -W exceptions=y --dir . main.wasm arg1 arg2
```

`--wasi` is wasm32 only, as no host runs wasm64 WASI modules.

**Hosts.** The host must implement the standard exception handling
instructions (exnref), as wasmtime 50 and node 22 do.

| host | command |
|------|---------|
| wasmtime | as above, with a `--dir` for each directory the program may use |
| node | `node:wasi` with `version: 'preview1'` and `preopens` (see `tests/wasi-run.mjs`) |
| wasmer | `wasmer run --volume DIR:/DIR main.wasm` (`--net` for WASIX, `--enable-tail-call` for compiled code) |

**What works.**

- **Files**: paths are resolved against the preopened directories, as
  wasi-libc does. `/tmp/x` is `x` in the directory preopened as `/tmp`,
  and a directory preopened as `.` holds every other path. Opening, reading,
  writing, `stat`, directories, renaming, removing, truncating, links and
  times work. An absolute symbolic link is followed through the preopened
  directories, which hosts refuse to do (core's `Timezone.local` needs
  `/etc/localtime` and `/usr/share/zoneinfo`, which it links into, both
  preopened).
  `Sys.chdir` and `Sys.getcwd` use a current directory kept by the
  program, `/` at first.
- **Waiting**: `Unix.sleep` and `Unix.select` wait for the host instead of
  spinning. `Sys.time` is the CPU time of the process, or the time since it
  started when the host has no CPU clock.
- **`Unix.dup` and `dup2`** of a file the program opened open it again at
  the same position, giving a copy with its own position. That is enough
  for a C library doing `fdopen(dup(fd))`, or to redirect `stdout` to a
  file. The
  standard streams cannot be duplicated.
- **Pipes** (`Unix.pipe`) are buffers in memory, between descriptors of
  the program, enough for the wake-up pipes of Async and lwt. Reading an
  empty pipe fails with `EAGAIN` rather than block, as nothing else can
  fill it. With threads (`--threads`), it waits for another thread to
  write. Each end takes a descriptor from the host,
  so a pipe needs a preopened directory (`--dir`).
- **lwt** (`Lwt_unix`, `Lwt_io`), core and async.

**Sockets.** WASI preview 1 has no call creating a socket.

- `--wasix` (or `wasix: yes` in `ocaml-emcc.conf`, for `--wasi`) uses
  WASIX's, wasmer's extension of preview 1: `Unix.socket`, `connect`,
  `bind`, `listen`, `accept`, `socketpair`, options, addresses, UDP,
  `getaddrinfo`, `getnameinfo` (numeric) and `gethostbyname` work, and so
  do lwt's sockets, with or without `--threads`. Only wasmer runs such a
  module (`wasmer run --net server.wasm`). Its `connect` always waits for
  the connection (its non-blocking one never completes), and some options
  of a listening socket cannot be read.
- Without `--wasix`, a program can only accept connections on the sockets
  its host preopens, the descriptors after the standard streams
  (`(Obj.magic 3 : Unix.file_descr)`), with no addresses nor options.
  wasmtime 46 preopens them (`-S preview2=n -S tcplisten=127.0.0.1:8080`),
  47 removed it.
- WASI preview 2's sockets need a component, which emscripten does not
  produce.

**What does not work.**

- Processes and `Sys.command` fail with `ENOSYS`.
- There are no users. Everything is owned by root, and `chmod` and
  `chown` do nothing.
- File locks (`fcntl`, `lockf`) always succeed, as there is a single
  process.
- C libraries that call functions emscripten implements in JavaScript
  (SDL, the `dlsym` of ctypes-foreign) keep importing them. `link` lists
  the imports that are not WASI, and such a module only runs where they
  are defined (`wasmtime -W unknown-imports-trap=y` runs it until one is
  called).

## JavaScript

### js_of_ocaml's library

Programs using [js_of_ocaml](https://ocsigen.org/js_of_ocaml)'s library
(`Js`, `Dom_html`, `Js.Unsafe`, its ppx's `o##m x`, `object%js`...), and
libraries built on it (js_of_ocaml-lwt, [Brr](https://erratique.ch/software/brr)), build
as is, interpreted or compiled, on both targets. ocaml-emcc implements
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

JavaScript values follow the conventions of wasm_of_ocaml, in a table on
the JavaScript side and a custom block on the OCaml side, released by the
GC. Code written for wasm_of_ocaml works unchanged.

**Differences with js_of_ocaml.**

- Each call goes from wasm to JavaScript and back: about 65 ns to read a
  property and 140 ns to call a method, compiled (the property names of
  the code are decoded once), 110 and 280 ns interpreted.
- `==` between two JavaScript values is physical equality of the OCaml
  blocks, false for two handles on the same object. `Js.equals` and
  `Js.strict_equals` compare the objects (as `Js.Opt` does).
- Typed arrays and bigarrays (`Typed_array`) are copied, not shared, as
  the wasm memory can move when it grows.
- An exception raised by the function of a `Sys_js` channel or mount point
  does not reach the program. The function is called from a system call,
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

ocamlc checks that the primitives of an executable exist, so link it with
`-no-check-prims` (`(link_flags (-no-check-prims))` with dune), as for
js_of_ocaml. Primitives can also be written in C and linked with `-l`.
These files use the conventions above, not those of js_of_ocaml's runtime
(whose strings are not JavaScript strings, among other differences). The
JavaScript files of js_of_ocaml libraries are not linked.

## wasm32 or wasm64

The bytecode is always the one of your switch, compiled for 64 bits. The
target is what the runtime and the C code are compiled for.

- **wasm32** (default) is smaller, faster and supported everywhere, but
  OCaml ints are 31 bits at run time (see below).
- **wasm64** (`--target wasm64`) has memory64 and exactly the semantics of
  the native 64-bit program, in fewer hosts (see
  [Environments](#environments)).

On wasm32, as with a 32-bit OCaml:

- Integer literals beyond 31 bits (`0x40000000`, `123456789012`) are
  wrapped when the program starts (`0x40000000` becomes `min_int`). This is
  right for code that picks 32-bit variants with `Sys.word_size` (optint,
  used by checkseum and decompress), wrong otherwise. `build`, `link` and
  `doctor` **warn** when there are any (the check is exact). Marshalled
  data holding such integers fails to load
  (`input_value: integer too large`).
- Arithmetic beyond 31 bits wraps silently (`1 lsl 40` is 256).

Packages that require 63-bit ints need wasm64, where matrix (its
`assert (Sys.int_size >= 62)`, hence k7 and kaun-board), binsec (its
marshalled data) and janestreet_cpuid (its flags) run. Two are patched to
run on wasm32 too. frama-c uses unionFind's identifiers patched for 31
bits, and `--node-fs` for its share directory (c_of_ocaml peaks at about
2 GB on it). rocq-runtime is rebuilt with its 31-bit integers and floats,
which it picks with `%{ocaml-config:int_size}`, 31 in the wasm32
toolchain.

Jane Street's libraries choose some of their code with the configuration
of jst-config, computed on the 64-bit host. On wasm32, `build` and `link`
rebuild jst-config and those of the program's libraries that read its
configuration, or were compiled against one whose interface differs
(core, and with it the async stack), for the target, as for ctypes (see
[internals](docs/internals.md#jane-streets-configuration)). The first
build of an async program takes some tens of minutes. core and async then
run on wasm32, interpreted or compiled, in node and with `--wasi`. Without
threads, the jobs of Async's thread pool (`In_thread.run`, file I/O...)
run synchronously.

## Plugins

A program can load plugins while it runs, parts of it compiled apart
that a web page fetches only when they are needed. The program uses the
library `ocaml-emcc.dynlink` (module `Emcc_dynlink`), and its bytecode is
linked with `-linkall` (`(link_flags (-linkall))`), since a plugin may use
any module of it (`tests/dynlink`, `tests/dynweb`).

```ocaml
(* in the program *)
let () =
  Emcc_dynlink.load_url "editor.wasm" (function
    | Ok () -> print_endline "the editor is loaded"
    | Error e -> prerr_endline (Printexc.to_string e))
```

```sh
ocaml-emcc build app.js     # or link app.bc -o app.js; --dynlink implied by Emcc_dynlink
ocaml-emcc plugin editor.cma -o editor.wasm --main app.js
```

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
  the C symbols plugins import (the runtime, and the stubs and C
  libraries the program links). Its compilation units are kept whole and
  registered by name, which makes the program bigger (1.6 MB for
  `tests/dynlink`, with the whole standard library).

**Limitations.**

- A plugin links the C libraries its `.cma` names (its stubs, built for
  the target when missing). The others it calls must be in the program
  (`plugin --main` checks it).
- Plugins cannot be unloaded.
- Effect handlers (OCaml 5): a program with plugins has them (double
  translation) when its own code performs effects, out of its dead code
  (`Stdlib.Effect`, kept whole by `-linkall`, does not count), or with
  `--cps-stack`, and a plugin built with `--main` follows the program
  (`tests/dyneffects`). An effect can then be performed by a plugin under
  a handler of the program, and the other way round. A program performing
  none needs `--effects double-translation` for plugins that do, as they
  may perform them through any of its functions (`List.iter`...), which
  must then have their CPS version. That doubles the size of the program
  (3.3 MB for `tests/dyneffects`), though its speed hardly changes.
  `plugin` refuses a plugin performing effects for a program without
  effect handlers (or without `--main`), unless `--effects disabled`
  (its effects then raise `Effect.Unhandled`), and a plugin built in the
  other mode than the program is refused when loaded.
- `cps-stack: yes` (`--cps-stack`) applies to a program loading plugins
  and to its plugins, whose deep recursions then go on in CPS too
  (`tests/dyncps`). `plugin --main` compiles a plugin with `--cps-stack`
  when the program has it, as does `plugin --cps-stack`. The program and
  its plugins then all have double translation, and a plugin built
  without effects has to be rebuilt. A plugin with double translation but
  without `--cps-stack` loads, its own recursions limited by the stack,
  the program's functions it calls not. The sizes add up: `-linkall`,
  double translation, then the CPS versions (about 60 % more than double
  translation alone for MOPSA).
- With `--threads`, `plugin --main` links a plugin for the program's
  shared memory, as does `plugin --threads`. The program's threads and
  the plugin's run the code of the plugins, and the callback of
  `load_url` runs after `main` (`tests/dynthreads`, and `tests/dynjspi`
  with `--jspi`).
- `Emcc_dynlink` is for the compiled mode, an interpreted program loads
  bytecode (see below).
- A program linked with asyncify (`-sASYNCIFY`, as raylib's) loads
  plugins, but must not suspend while the code of a plugin is on the
  stack, as asyncify only instruments the program. JSPI (`--jspi`) has no
  such limit.

**Interpreted.** An interpreted program loads bytecode plugins, `.cmo`
and `.cma` files, with OCaml's `Dynlink`, as `ocamlrun` does
(`tests/dynbyte`). Plugins written in OCaml only need nothing more. Those with C
stubs of their own (the `dllX.so` their `.cma` names) need the program
linked with `--dynlink` too, and their stubs built as wasm side modules.

```sh
ocaml-emcc build app.js --interpreted --dynlink
ocaml-emcc plugin cst.cma --main app.js -o stublibs   # stublibs/dllcst.so, from the wasm libcst.a
```

- `plugin --interpreted` (or `--main` naming an interpreted program)
  links each `dllX.so` of the `.cma` from its wasm `libX.a`, found next to
  the `.cma` or in the sysroot, and built when missing, as for a program.
  The `.cma` itself is the plugin. `str.cma` loads that way in a program
  that does not link `Str`.
- `Dynlink` looks for `dllX.so` in `CAML_LD_LIBRARY_PATH`, which may name
  the host's (with `--node-fs`, those of the opam switch). The program
  then loads the wasm one of `$OCAML_EMCC_STUBLIBS` or the current
  directory instead, and says so when there is none. In a browser, put
  them in emscripten's file system (`--preload-file`).
- The C a plugin calls and does not link (libc's functions the program
  does not use) is missing, which `--main` checks.

## Threads

```sh
ocaml-emcc build main.js --threads
ocaml-emcc build main.wasm --wasi --threads
wasmer run main.wasm                # or wasmtime <= 46:
wasmtime run -W exceptions=y,threads=y,shared-memory=y -S threads=y --dir . main.wasm
```

With `--threads` (or `threads: yes` in `ocaml-emcc.conf`), `Thread.create`
starts a real thread, and so does `Domain.spawn` with OCaml 5.3 or later
(domains run in parallel). `Mutex`, `Condition`, `Event`, `Atomic` and
`Domain.DLS` work as natively, compiled (the generated code polls in its
loops and before its tail calls, so that a thread computing lets the
others run) or interpreted.

| | with `--threads` | without |
|-|------------------|---------|
| `Thread.create`, `Domain.spawn` | real threads | fail |
| `Mutex`, `Condition` | yes | yes |
| lwt's blocking jobs (`Lwt_unix` file operations...) | in its pool of threads | run synchronously |
| `Lwt_preemptive` | yes | fails |
| Async's `In_thread.run` | in its thread pool | runs synchronously |

The C code is compiled for threads either way (`-pthread`), with no
measurable cost.

**node and browsers.** Threads are web workers sharing the memory of the
program (emscripten's pthreads).

- The program's main thread is a worker too (`-sPROXY_TO_PTHREAD`), so the
  JavaScript thread stays free to run what the others ask it (emscripten's
  file system is there) and to start their workers.
- In a browser, the page must be cross-origin isolated, served with the
  headers `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` (SharedArrayBuffer).
- Programs using js_of_ocaml's primitives keep their main thread on the
  page's, for the DOM. Their workers are started before the program, 8 of
  them (OCaml's tick thread included, `-sPTHREAD_POOL_SIZE=N` sets it),
  since a browser only starts a new one once that thread is back in its
  event loop. A program waiting for more threads than that at once blocks
  forever. That thread waits by spinning, and runs the other threads' file
  operations only when it waits.
- JavaScript values belong to that main thread, as the page does. The
  other threads work in OCaml and pass their results through it (a
  `Mutex`, an `Event`...). A call to JavaScript from one of them raises
  `Failure` (`tests/jsthreads`, `tests/jsthreadsweb`). Once main returned,
  the other threads go on between the callbacks.
- Compiled, under node, every thread gets the large stack of the main one
  (`$OCAML_EMCC_STACK_MB`).

**WASI.** Threads use wasi-threads (`thread-spawn`), the ABI of wasi-libc's
`wasm32-wasip1-threads`, which wasmer 7.5 and wasmtime up to 46 run, as
above (wasmtime 47 removed it). The module imports its memory, shared. `Domain.recommended_domain_count` is
`$OCAML_EMCC_CPUS`, or 4.

The runtime reserves the minor heaps of the possible domains at startup,
8 by default (32 MB on wasm32, 16 MB on wasm64). `OCAMLRUNPARAM=d=N` sets
the number.

## Differences from native

Besides 31-bit integers on wasm32 (see [wasm32 or
wasm64](#wasm32-or-wasm64)):

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
  stub written for one OS only, such as Linux's epoll or Windows') becomes
  a stub raising `Failure "NAME not implemented"` when called, as with
  js_of_ocaml. `link` warns, and a program that never calls it runs.
  `--no-missing-primitives` makes it a link error instead.
- **C type mismatches.** A C function declared by a stub with other types
  than its definition (`int` for `long`) becomes a trap on wasm64. `link`
  warns about each one.
- **Time zone**: emscripten's file system in memory has `/etc/localtime`
  (also under its name in `/usr/share/zoneinfo`), the host's under node
  (that of `$TZ`), made from the browser's time zone in browsers, exact
  from 1970 to 2037.
- **File mappings** (`Unix.map_file`, `mmap`) are copies of the file, with
  emscripten's glue and under `--wasi`. A shared writable one is written
  back to the file by `msync` and `munmap`, the finalizer of the bigarray
  (`tests/mapfile`): its writes do not show in the file before, nor the
  file's writes in it.
- **Floating-point rounding modes** do not exist in wasm. Only
  round-to-nearest is available, so code that switches to directed rounding
  (`fesetround`) loses that guarantee.

## C dependencies

### What is built automatically

Most programs need no configuration. `build` and `link` find the C a
program needs from its bytecode and its opam packages.

- **Stub libraries of opam packages** are rebuilt with emcc from the
  package that installed them, with the builtin recipe of that package if
  there is one, else with the package's own dune rules, else from the C
  files of its native build. Those built with dune
  or from the native build are built again when the package changes
  version, and when ocaml-emcc's toolchain wrappers change.
- **System C libraries**: a package depending on `conf-gmp`,
  `conf-zlib`... gets the recipe of the same name built and linked. So is
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
- **Packages with a build of their own**: the `make`, `configure`, CMake or
  shell scripts that a dune rule runs get emcc, emar and emranlib under the
  host's names (`cc`, `gcc`, `g++`, `clang`, `ar`, `ranlib`...), and CMake
  finds the sysroot's libraries first (qbf's picosat, re2's C++ library,
  cudd, hdr_histogram). Stub libraries that dune skips for the target, as
  enabled for some architectures only (curve448), are compiled from the C
  files of the native build.
- **ctypes**: bindings using stub generation (`Cstubs`, dune's `(ctypes)`
  stanza) and ctypes-foreign work on both targets.

A recipe is built once per switch and target, and is not rebuilt when it
changes (ocaml-emcc says so). `ocaml-emcc install --force NAME` rebuilds
it.

### Builtin recipes

| recipe | for (opam) | notes |
|--------|------------|-------|
| `gmp`, `mpfr` | zarith, mlmpfr, mlgmpidl, apron, class_group_vdf (gmpxx)... | gmp with its C++ interface |
| `zlib` | camlzip, zlib | |
| `sqlite3` | sqlite3 | amalgamation, thread-safe, FTS3/4/5, R-tree, math functions (`SQLITE_CFLAGS`) |
| `libffi` | ctypes-foreign | |
| `libbz2` | bz2 | |
| `libpcre2-8` | pcre2 | no JIT |
| `libpcre` | pcre | PCRE 8.45 (the last one), UTF-8 and Unicode properties, no JIT |
| `zstd` | zstd | single-threaded |
| `gsl` | gsl | with its CBLAS |
| `liblz4` | lz4 | |
| `snappy` | snappy | C++ |
| `expat` | ocaml-expat | |
| `fftw3` | fftw3 | double and single precision, no threads or SIMD |
| `glpk` | glpk | |
| `libargon2` | argon2 | reference implementation, no threads |
| `liblmdb` | lmdb | `MDB_NOLOCK \| MDB_WRITEMAP`, as emscripten has no process-shared mutexes and its file mappings are copies |
| `sdl2` | tsdl | emscripten's port (`-sUSE_SDL=2`), only the timer and events subsystems under node |
| `glfw3` | glfw-ocaml | emscripten's (`-sUSE_GLFW=3`), WebGL 2, no gamepads, a window needs a web page |
| `libev` | lwt (when the host's uses it) | poll backend |
| `libssl` | ssl | OpenSSL in generic C |
| `ffmpeg` | ffmpeg-avutil, ffmpeg-avcodec... | its own codecs, formats and filters, in generic C, without threads, networking or external libraries |
| `cairo` (`pixman`, `libpng`, `freetype`, `libfontconfig`) | cairo2 | image, PDF, PostScript, SVG and script surfaces, FreeType fonts (fontconfig finds the host's fonts under node), no X11, pixman without SIMD, built with meson (and gperf) |
| `oniguruma` | oniguruma | |
| `secp256k1` | secp256k1 | recovery, ECDH, extrakeys, schnorrsig, ellswift and musig modules, the host's minor version |
| `libogg`, `libopus` | ogg, opus | opus without intrinsics |
| `mad` | mad | 64-bit fixed point, no assembly |
| `faad` | faad | |
| `shine` | shine | |
| `ncurses` | curses | wide-character libraries, the host's terminfo under node, more than 64 KB of stack needed |
| `libjpeg`, `gd` | gd | libjpeg-turbo without SIMD, libgd with PNG, JPEG and FreeType |
| `liblo` | lo | Open Sound Control (its server thread needs `--threads`) |
| `openblas` | lacaml, nx, owl... (`-lblas`, `-llapack` too) | BLAS, CBLAS, LAPACK and LAPACKE in C (no Fortran), generic kernels, no threads, its subroutines' C signatures made to agree (wasm traps on a mismatch), 30 to 40 minutes to build on one core |
| `lame` | lame | libmp3lame, no assembly |
| `libevent` | libevent | poll and select backends, no OpenSSL |
| `liblzo2` | lzo | |
| `nlopt` | nlopt | its C algorithms (not StoGO or AGS, in C++) |
| `frei0r` | frei0r | its header only, no plugins |
| `gdbm` | dbm | GNU dbm, without readline or NLS |
| `zmq` | zmq | libzmq in C++, with poll, without CURVE (libsodium) or the draft API |
| `readline` | readline | GNU readline and history, with ncurses |
| `libcurl` | curl | with OpenSSL, zlib and the blocking resolver, without HTTP/2, HTTP/3, IDN, PSL, brotli, zstd, LDAP or SSH |
| `mariadb` | mysql, mariadb | MariaDB Connector/C, static, with OpenSSL and zlib, its authentication plugins built in |
| `clang` | programs embedding clang's frontend | see [docs/recipes.md](docs/recipes.md#the-clang-recipe) |

These recipes take the sources of the opam package that vendors the
library if the switch has it, else the newest upstream release compatible
with the host's library (see [system
recipes](docs/recipes.md#system-recipes)).

Recipes of OCaml packages, built from the sources of the installed package,
cover `zarith`, `camlidl`, `mlgmpidl`, `apron` (every domain and numeric
variant), `mlcuddidl` (its bundled CUDD, and the stubs camlidl generates),
`hacl-star-raw` (portable C only, the vectorized and Vale variants trap if
called), and, with sources changed for wasm (see their
`share/recipes/<name>/` directory), `mirage-crypto` (and `-ec`, `-rng`),
`lwt`, `cryptokit`, `secp256k1-internal`, `lmdb`, `mccs`, `core_unix`,
`async_unix`, `async_ssl`, `eio_posix`, `num`, `rowex`, `mirage-block-unix`,
`shared-memory-ring`, `ocaml_intrinsics`, `unix-errno`, `tuntap`, `eigen`,
`bls12-381`, `bls12-381-signature`, `janestreet_cpuid`, `shell`,
`rocq-runtime`, `hdr_histogram`, `codex`, `unionFind`, `miou`, `osdp`,
`bls12-381-unix`, `lacaml`, `setcore`, `cpu`, `memcpy`, `scrypt`, `poll`,
`bytesrw`, `class_group_vdf`, `ocaml-lua` and `raylib` (see [raylib in a
browser](#raylib-in-a-browser)).

### Project recipes

A project recipe lives in `emcc-recipes/<name>/recipe.sh` next to
`dune-project`, is listed in `requires:` and linked with `link-flags:` in
[`ocaml-emcc.conf`](#configuration). This one clones cJSON
(`tests/gitrecipe`).

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

A project recipe can also **refine** a builtin one. `include_recipe NAME`
reads the next recipe of that name, after the project's variables are set,
and an optional `pre_build` function runs before its `build`, to patch the
sources. [MOPSA](https://github.com/rboudrouss/mopsa-emcc/tree/ocaml-emcc)
pins clang 9 and patches apron this way.

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

## Without dune

Run the steps of `build` (see [Commands](#commands-and-options)) yourself:
build the bytecode however you like, compile your stubs with
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
rebuilt for the target, with
`OCAMLFIND_CONF=<sysroot>/findlib.conf ocamlfind -toolchain wasm32 ocamlc ...`
(or `-toolchain wasm64`). `link` warns otherwise.

## How it works

[docs/internals.md](docs/internals.md) details each step of
[`build`](#quick-start), standalone and WASI modules, ctypes, the flags
used for all C code and the workarounds for each OCaml version.

## Status

The test suite ([tests/README.md](tests/README.md)) builds about 40
programs with C stubs (zarith, apron, sqlite3, ctypes, lwt, mirage-crypto,
hacl-star, mccs, sdl...) and compares their output under node with that
of the native executable. It passes on both targets and under WASI,
compiled and interpreted, except `ctypes` on wasm64 (libffi's calls stop
on "Unexpected type 0" with emsdk 6.0.11), in CI as [the table
says](#compiled-or-interpreted). For
0.3.0 (interpreted only then) it passed on every OCaml version from 4.08
to 5.5, and its WASI part with wasmtime 50.

### Versions of the dependencies

`tests/versions.sh` installs each version of a package in turn (opam takes
its dependents along), runs the tests about it, and puts the packages of
the switch back. These results are on wasm32, with OCaml 4.14.2.

| tests | package | versions that pass | others |
|-------|---------|--------------------|--------|
| `zarith` | zarith | 1.11, 1.12, 1.13, 1.14 | |
| `mixed` | digestif | 1.1.2, 1.3.0, 1.4.1 | |
| `sqlite` | sqlite3 | 5.0.3, 5.2.0, 5.4.2 | |
| `zstd` | zstd | 0.4 | 0.3 (the test uses later functions) |
| `gsl` | gsl | 1.24.3, 1.25.1 | 1.22.0 (not installable on OCaml 4.14) |
| `camlzip` | camlzip | 1.11, 1.13, 1.14 | |
| `ctypes`, `cstanza` | ctypes, ctypes-foreign | 0.21.1, 0.22.0, 0.23.0, 0.24.0 | 0.20.2, built by make, cannot be rebuilt for wasm32, so its layouts are the host's (`link` warns) |
| `yaml` | yaml | 3.0.1, 3.1.0, 3.2.0 | |
| `mcrypto` | mirage-crypto | 2.4.1 | 2.0.2, 2.2.0 (the test uses later functions) |
| `lwt` | lwt | 5.6.1, 5.9.2, 6.1.2 | |
| `cryptokit` | cryptokit | 1.21.1 | 1.20 (the test uses later functions) |
| `secp` | secp256k1-internal | 0.3.1, 0.4.0 | |
| `apron` | apron | v0.9.14, v0.9.15 | v0.9.13 (does not build natively with GCC 14) |
| `extunix` | extunix | 0.4.4 | 0.3.2, 0.4.1 (`splice.c` returns a `value *` as an `off_t *`, an error on 32-bit targets) |
| `stb` | stb_image | 0.4, 0.5 | |
| `minisat` | minisat | 0.4, 0.6 | |
| `cudd` | mlcuddidl | 3.0.8 | 3.0.6, 3.0.7 (do not build natively with GCC 14) |
| `hacl` | hacl-star | 0.7.2 | 0.5.0, 0.6.2 (the test uses later modules, `K256`) |
| `posix` | posix-time2, -socket, -stat | 4.0.2 | 2.2.0, 3.0.0 (no posix-stat) |
| `mccs` | mccs | 1.1+13, 1.1+17, 1.1+19 | |
| `raylib` | raylib | 2.2.2, 2.3.0, master (bd831de) | |

The recipes' patches (placed by their text, see
[patches](docs/recipes.md#patches)) were also checked to apply, as GNU
patch applied the previous ones, to the
sources of every OCaml version from 4.08 to 5.5 and of lwt 5.4 to 6.1,
mirage-crypto 0.11 to 2.4, cryptokit 1.16 to 1.21, secp256k1-internal 0.3
and 0.4, lmdb 1.1, dune 3.12 to 3.24 and mccs 1.1+13 to 1.1+19.

## Next steps

- Propose the patch of dune's `(ctypes)` stanza upstream
  ([ocaml/dune#13650](https://github.com/ocaml/dune/issues/13650)), so that
  the switch's dune can build it.
- More recipes: ppl (C++, apron's `ppl` and `polkaGrid` domains), flint,
  libtidy, and newer LLVM versions for `clang`.
- A WASI `dlsym` that needs no JavaScript (a table of the exported
  functions generated by `link`), though ctypes-foreign would still need a
  libffi without JavaScript. WASI preview 2 (components, its sockets) is
  not targeted.

## License

ocaml-emcc is distributed under the MIT license (`LICENSE`), except
`share/runtime/jsoo.js`, the JavaScript side of js_of_ocaml's primitives,
parts of which are adapted from js_of_ocaml's runtime. It is distributed
under js_of_ocaml's license, the GNU LGPL version 2.1 or later, with a
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
