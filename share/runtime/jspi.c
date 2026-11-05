/* Linked by `ocaml-emcc link --jspi` with compiled code: the new stacks of
 * c_of_ocaml's segmented stack (camlc_host_new_stacks and
 * camlc_host_on_new_stack, see its camlc.h), with JSPI (emcc's -sJSPI).
 * Without them (no --jspi, or a standalone module), the weak definitions of
 * camlc_runtime.c run everything on the stack of the engine.
 *
 * Main runs in a context which can suspend.  ocaml_emcc_jspi_switch
 * suspends it, until ocaml_emcc_jspi_run has called the function on a new
 * stack, in a new context.  The call is delayed to a microtask, so that the
 * JavaScript function returns and its frame does not stay on the stack of
 * the engine. */

#include <emscripten/em_js.h>

EM_JS(int, ocaml_emcc_jspi_available, (void), {
  return typeof Asyncify == 'object' &&
    typeof Asyncify.makeAsyncFunction == 'function' &&
    typeof WebAssembly.promising == 'function';
});

EM_ASYNC_JS(void, ocaml_emcc_jspi_switch, (void), {
  await 0;
  if (!Module.ocamlEmccJspiRun)
    Module.ocamlEmccJspiRun = WebAssembly.promising(wasmExports['ocaml_emcc_jspi_run']);
  await Module.ocamlEmccJspiRun();
});

static _Thread_local void (*ocaml_emcc_jspi_f)(void);

EMSCRIPTEN_KEEPALIVE void ocaml_emcc_jspi_run(void) { ocaml_emcc_jspi_f(); }

int camlc_host_new_stacks(void) { return ocaml_emcc_jspi_available(); }

void camlc_host_on_new_stack(void (*f)(void))
{
  ocaml_emcc_jspi_f = f;
  ocaml_emcc_jspi_switch();
}
