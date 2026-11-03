/* The primitives of the library ocaml-emcc.dynlink (Emcc_dynlink), which
 * loads plugins built by `ocaml-emcc plugin`: emscripten side modules whose
 * entry point camlc_plugin_init (c_of_ocaml) registers and initializes
 * their compilation units.  `link` compiles this file in instead of the
 * library's stubs, with OCAML_EMCC_DYNLINK for a program linked with
 * --dynlink (a main module); without it, loading fails. */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <dlfcn.h>
#include <unistd.h>
#include <emscripten.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/printexc.h>

/* printexc.h declares it with CAML_INTERNALS only */
extern void caml_fatal_uncaught_exception(value exn);

#ifdef OCAML_EMCC_DYNLINK

/* The TLS block of the main thread: dynlink.js turns the offsets of the
   thread-local variables the program exports into addresses for its
   plugins */
EMSCRIPTEN_KEEPALIVE void *ocaml_emcc_tls_base(void) { return __builtin_wasm_tls_base(); }

#ifdef OCAML_EMCC_DOUBLE_TRANSLATION
/* Exported by a program compiled with effects (--effects
   double-translation): `ocaml-emcc plugin --main` compiles its plugins the
   same way, which camlc_plugin_init requires */
EMSCRIPTEN_KEEPALIVE void ocaml_emcc_double_translation(void) {}
#endif

static void fail_dl(const char *what, const char *file)
{
  char buf[1024];
  const char *e = dlerror();
  snprintf(buf, sizeof buf, "Emcc_dynlink.%s %s: %s", what, file, e ? e : "cannot load");
  caml_failwith(buf);
}

/* Runs the plugin: called from OCaml, as camlc_plugin_init must be */
static value run(void *h, const char *file)
{
  value (*init)(void) = (value (*)(void))dlsym(h, "camlc_plugin_init");
  if (init == NULL) {
    char buf[1024];
    snprintf(buf, sizeof buf,
             "Emcc_dynlink: %s is not a plugin (no camlc_plugin_init, see `ocaml-emcc plugin`)", file);
    caml_failwith(buf);
  }
  return init();
}

CAMLprim value caml_emcc_dynlink_loadfile(value path)
{
  void *h;
  /* dlopen would fetch it synchronously, which fails in a web page (and
     leaves an entry that a second dlopen takes for the plugin) */
  if (access(String_val(path), R_OK) != 0) {
    char buf[1024];
    snprintf(buf, sizeof buf, "Emcc_dynlink.loadfile %s: no such file (load_url fetches a plugin)",
             String_val(path));
    caml_failwith(buf);
  }
  h = dlopen(String_val(path), RTLD_NOW | RTLD_LOCAL);
  if (h == NULL) fail_dl("loadfile", String_val(path));
  return run(h, String_val(path));
}

CAMLprim value caml_emcc_dynlink_run(value h)
{
  return run((void *)(uintptr_t)Nativeint_val(h), "the plugin");
}

/* The asynchronous dlopen of emscripten (a fetch in a web page): its
   callbacks call the OCaml continuation (root in a malloc'd cell) with
   Ok handle or Error message. */

static void resume(void *cell, value result)
{
  value k = *(value *)cell, r;
  caml_remove_generational_global_root(cell);
  free(cell);
  r = caml_callback_exn(k, result);
  if (Is_exception_result(r)) caml_fatal_uncaught_exception(Extract_exception(r));
}

static void opened(void *cell, void *h)
{
  CAMLparam0();
  CAMLlocal2(r, n);
  n = caml_copy_nativeint((intnat)(uintptr_t)h);
  r = caml_alloc_small(1, 0); /* Ok */
  Field(r, 0) = n;
  resume(cell, r);
  CAMLreturn0;
}

static void failed(void *cell)
{
  CAMLparam0();
  CAMLlocal2(r, s);
  const char *e = dlerror();
  s = caml_copy_string(e ? e : "cannot load the plugin");
  r = caml_alloc_small(1, 1); /* Error */
  Field(r, 0) = s;
  resume(cell, r);
  CAMLreturn0;
}

CAMLprim value caml_emcc_dynlink_open_async(value url, value k)
{
  value *cell = malloc(sizeof(value));
  if (cell == NULL) caml_raise_out_of_memory();
  *cell = k;
  caml_register_generational_global_root(cell);
  emscripten_dlopen(String_val(url), RTLD_NOW | RTLD_LOCAL, cell, opened, failed);
  return Val_unit;
}

#else

static void no_dynlink(void)
{
  caml_failwith("Emcc_dynlink: the program is not linked for plugins (ocaml-emcc link/build --dynlink)");
}

CAMLprim value caml_emcc_dynlink_loadfile(value path) { (void)path; no_dynlink(); return Val_unit; }
CAMLprim value caml_emcc_dynlink_run(value h) { (void)h; no_dynlink(); return Val_unit; }
CAMLprim value caml_emcc_dynlink_open_async(value url, value k) { (void)url; (void)k; no_dynlink(); return Val_unit; }

#endif
