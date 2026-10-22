(lang dune 3.11)
(name ocaml-emcc)
(generate_opam_files true)
(license MIT)
(authors "rboudrouss <r.boudrouss@gmail.com>")
(maintainers "rboudrouss <r.boudrouss@gmail.com>")
(source (github rboudrouss/ocaml-emcc))

(package
 (name ocaml-emcc)
 (synopsis "Compile OCaml programs with C stubs to WebAssembly with emscripten")
 (description
  "ocaml-emcc runs OCaml bytecode on an emscripten build of ocamlrun and \
   links the C stubs of the program and of its dependencies statically, \
   which makes FFI-heavy libraries (zarith/gmp, apron, libclang...) usable \
   in the browser and in node. The runtime is rebuilt from the sources of \
   the switch's own compiler (any version from 4.08, including 5.x), C libraries \
   come from recipes. \
   Requires the emscripten SDK (emsdk) in PATH.")
 (depends
  (ocaml (>= 4.08))))
