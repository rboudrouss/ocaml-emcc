/* Outside of ocaml-emcc: plugins cannot be loaded (see share/runtime/dynlink.c) */

#include <caml/mlvalues.h>
#include <caml/fail.h>

static void unavailable(void)
{
  caml_failwith("Emcc_dynlink: only in programs linked by ocaml-emcc --dynlink (compiled)");
}

value caml_emcc_dynlink_loadfile(value path) { (void)path; unavailable(); return Val_unit; }
value caml_emcc_dynlink_run(value h) { (void)h; unavailable(); return Val_unit; }
value caml_emcc_dynlink_open_async(value url, value k) { (void)url; (void)k; unavailable(); return Val_unit; }
