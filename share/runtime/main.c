/* Entry point of the wasm executables produced by `ocaml-emcc link`.
 *
 * The bytecode is shipped in the emscripten virtual file system (embedded or
 * preloaded at OCAML_EMCC_BYTECODE).  ocamlrun's startup first tries to open
 * argv[0] as a bytecode executable (this is how `ocamlc -custom` programs
 * work), so pointing argv[0] at the bytecode is enough: Sys.argv then looks
 * exactly like the one of a native executable. */

#define CAML_INTERNALS
#include <caml/mlvalues.h>
#include <caml/callback.h>
#include <caml/sys.h>

/* Exists in every version; declared in <caml/sys.h> only before 5.0
   (caml_do_exit, its replacement, only exists since 4.14). */
extern value caml_sys_exit(value);

#ifndef OCAML_EMCC_BYTECODE
#define OCAML_EMCC_BYTECODE "/ocaml/main.bc"
#endif

/* OCAML_EMCC_BYTECODE=0: argv[0] is already the bytecode path (node with the
   real file system, see `ocaml-emcc link --node-fs`). */
static const char *ocaml_emcc_bytecode = OCAML_EMCC_BYTECODE;

int main(int argc, char **argv)
{
  (void)argc;
  if (ocaml_emcc_bytecode) argv[0] = (char *)ocaml_emcc_bytecode;
  caml_main(argv);
  caml_sys_exit(Val_int(0));
  return 0;
}
