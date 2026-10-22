/* dlopen/dlsym for programs linked statically, as every ocaml-emcc program
 * is.  ctypes-foreign looks up the C functions it binds with dlsym
 * (Foreign.foreign "strlen"), which emscripten only supports with dynamic
 * linking.  `ocaml-emcc link` compiles this file in when the bytecode uses
 * ctypes_dlsym, and exports the C symbols named by its string literals:
 * dlsym finds them among the module's exports.  A function gets a slot in
 * the function table (a function pointer is a table index), a data symbol is
 * exported as a global holding its address.  Every library is in the
 * program: dlopen succeeds for any file name and dlsym searches everything. */

#include <stdint.h>
#include <emscripten.h>

EM_JS_DEPS(ocaml_emcc_dlsym, "$addFunction,$UTF8ToString");

/* table index of exported function NAME, 0 if there is none */
EM_JS(int, ocaml_emcc_dlsym_func, (const char *name), {
  var n = UTF8ToString(Number(name));
  /* the wasm function, not a JS wrapper (see keep_raw_exports in link.ml) */
  var f = (Module['ocamlEmccRawExports'] || wasmExports)[n];
  if (typeof f !== 'function') return 0;
  var cache = Module['ocamlEmccDlsym'] || (Module['ocamlEmccDlsym'] = {});
  if (!(n in cache)) cache[n] = Number(addFunction(f));
  return cache[n];
});

/* address of exported data symbol NAME, -1 if there is none */
EM_JS(double, ocaml_emcc_dlsym_data, (const char *name), {
  var g = (Module['ocamlEmccRawExports'] || wasmExports)[UTF8ToString(Number(name))];
  return (g instanceof WebAssembly.Global) ? Number(g.value) : -1;
});

/* musl's: its dlerror (always linked) returns the message set by this */
void __dl_seterr(const char *fmt, ...);

static char the_handle;

void *dlopen(const char *file, int flags)
{
  (void)file; (void)flags;
  return &the_handle; /* any non-null handle */
}

void *dlsym(void *handle, const char *name)
{
  int f;
  double d;
  (void)handle;
  if ((f = ocaml_emcc_dlsym_func(name)) != 0) return (void *)(uintptr_t)f;
  if ((d = ocaml_emcc_dlsym_data(name)) >= 0) return (void *)(uintptr_t)d;
  __dl_seterr("%s: undefined symbol (ocaml-emcc exports the C symbols named by string "
              "literals of the program, from the linked libraries)", name);
  return NULL;
}

int dlclose(void *handle)
{
  (void)handle;
  return 0;
}
