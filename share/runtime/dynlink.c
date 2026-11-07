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
extern value caml_sys_exit(value);

#if defined(OCAML_EMCC_DYNLINK) || defined(OCAML_EMCC_BYTECODE_DLLS)
/* The TLS block of the main thread: dynlink.js turns the offsets of the
   thread-local variables the program exports into addresses for its
   plugins */
EMSCRIPTEN_KEEPALIVE void *ocaml_emcc_tls_base(void) { return __builtin_wasm_tls_base(); }
#endif

#ifdef OCAML_EMCC_DYNLINK

#ifdef OCAML_EMCC_DOUBLE_TRANSLATION
/* Exported by a program c_of_ocaml compiled with effects (double
   translation, as its manifest says): `ocaml-emcc plugin --main` compiles
   its plugins the same way, which camlc_plugin_init requires */
EMSCRIPTEN_KEEPALIVE void ocaml_emcc_double_translation(void) {}
#endif

#ifdef OCAML_EMCC_CPS_STACK
/* Exported by a program compiled with --cps-stack: `ocaml-emcc plugin
   --main` compiles its plugins with it too, their deep recursions going on
   in CPS (c_of_ocaml then compiles them with double translation, as the
   program) */
EMSCRIPTEN_KEEPALIVE void ocaml_emcc_cps_stack(void) {}
#endif

#ifdef OCAML_EMCC_THREADS
/* Exported by a program linked with --threads, whose memory is shared:
   `ocaml-emcc plugin --main` links its plugins with -pthread, which
   import it */
EMSCRIPTEN_KEEPALIVE void ocaml_emcc_threads(void) {}
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

/* The loads not finished yet, and whether main returned before them (in a
   pthread, with threads: see main.c, the last of them then exits) */
int ocaml_emcc_dynlink_pending = 0;
int ocaml_emcc_main_returned = 0;

static void resume(void *cell, value result)
{
  value k = *(value *)cell, r;
  caml_remove_generational_global_root(cell);
  free(cell);
  r = caml_callback_exn(k, result);
  if (Is_exception_result(r)) caml_fatal_uncaught_exception(Extract_exception(r));
  if (--ocaml_emcc_dynlink_pending == 0 && ocaml_emcc_main_returned) caml_sys_exit(Val_int(0));
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
  ocaml_emcc_dynlink_pending++;
  emscripten_dlopen(String_val(url), RTLD_NOW | RTLD_LOCAL, cell, opened, failed);
  return Val_unit;
}

#else

static void no_dynlink(void)
{
#ifdef OCAML_EMCC_BYTECODE_DLLS
  caml_failwith("Emcc_dynlink loads compiled plugins, and the program is interpreted: Dynlink loads bytecode ones");
#else
  caml_failwith("Emcc_dynlink: the program is not linked for plugins (ocaml-emcc link/build --dynlink)");
#endif
}

CAMLprim value caml_emcc_dynlink_loadfile(value path) { (void)path; no_dynlink(); return Val_unit; }
CAMLprim value caml_emcc_dynlink_run(value h) { (void)h; no_dynlink(); return Val_unit; }
CAMLprim value caml_emcc_dynlink_open_async(value url, value k) { (void)url; (void)k; no_dynlink(); return Val_unit; }

#endif

#ifdef OCAML_EMCC_BYTECODE_DLLS

/* An interpreted program linked with --dynlink (a main module): the
   interpreter's Dynlink loads the C of bytecode plugins, the dllX.so their
   .cma names, which `ocaml-emcc plugin --interpreted` builds as emscripten
   side modules.  Dynlink finds them in CAML_LD_LIBRARY_PATH, which may
   name the host's (with --node-fs, an opam switch's stublibs): dlopen
   (-Wl,--wrap=dlopen) then looks for the wasm one in the directories of
   $OCAML_EMCC_STUBLIBS, then in the current directory. */

/* Read by `ocaml-emcc plugin --main`: the plugins of an interpreted
   program are its .cma files and their wasm dllX.so */
EMSCRIPTEN_KEEPALIVE void ocaml_emcc_interpreted(void) {}

#ifdef OCAML_EMCC_THREADS
EMSCRIPTEN_KEEPALIVE void ocaml_emcc_threads(void) {}
#endif

extern void *__real_dlopen(const char *path, int flags);
extern char *__real_dlerror(void);

static char dl_error[1024];

static int is_wasm(const char *path)
{
  unsigned char m[4];
  FILE *f = fopen(path, "rb");
  int ok = f != NULL && fread(m, 1, 4, f) == 4 && m[0] == 0 && m[1] == 'a' && m[2] == 's' && m[3] == 'm';
  if (f != NULL) fclose(f);
  return ok;
}

/* NAME in $OCAML_EMCC_STUBLIBS or the current directory, if wasm. */
static void *open_wasm(const char *name, int flags)
{
  const char *dirs, *d;
  char buf[4096];
  dirs = getenv("OCAML_EMCC_STUBLIBS");
  for (d = dirs; d != NULL && *d != 0;) {
    const char *e = strchr(d, ':');
    size_t n = e != NULL ? (size_t)(e - d) : strlen(d);
    if (n > 0) {
      snprintf(buf, sizeof buf, "%.*s/%s", (int)n, d, name);
      if (is_wasm(buf)) return __real_dlopen(buf, flags);
    }
    d = e != NULL ? e + 1 : NULL;
  }
  if (is_wasm(name)) return __real_dlopen(name, flags);
  return NULL;
}

void *__wrap_dlopen(const char *path, int flags)
{
  const char *base;
  char stem[1024], name[1040];
  char *dash;
  void *h;
  if (path == NULL || is_wasm(path)) return __real_dlopen(path, flags);
  base = strrchr(path, '/');
  base = base != NULL ? base + 1 : path;
  if ((h = open_wasm(base, flags)) != NULL) return h;
  /* OCaml 5.5 asks for dllNAME-<target>-<bytecode-runtime-id>.so, `plugin`
     builds dllNAME.so: drop the suffix, a word at a time. */
  snprintf(stem, sizeof stem, "%s", base);
  if (strlen(stem) > 3 && strcmp(stem + strlen(stem) - 3, ".so") == 0) stem[strlen(stem) - 3] = 0;
  while ((dash = strrchr(stem, '-')) != NULL && dash > stem + 3) {
    *dash = 0;
    snprintf(name, sizeof name, "%s.so", stem);
    if ((h = open_wasm(name, flags)) != NULL) return h;
  }
  snprintf(dl_error, sizeof dl_error,
           "%s, and no wasm %s in $OCAML_EMCC_STUBLIBS nor the current directory "
           "(`ocaml-emcc plugin --interpreted LIB.cma` builds it)",
           access(path, R_OK) == 0 ? "not wasm" : "not found", base);
  return NULL;
}

char *__wrap_dlerror(void)
{
  static char last[sizeof dl_error];
  if (dl_error[0] == 0) return __real_dlerror();
  memcpy(last, dl_error, sizeof last);
  dl_error[0] = 0;
  return last;
}

#endif
