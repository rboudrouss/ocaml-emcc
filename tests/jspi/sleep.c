/* emscripten_sleep, which suspends the program (JSPI instead of asyncify):
   gives the event loop a turn, as raylib's window_should_close does */
#include <emscripten.h>
#include <caml/mlvalues.h>
#include <caml/callback.h>

value jp_sleep(value ms)
{
  emscripten_sleep(Int_val(ms));
  return Val_unit;
}

/* OCaml called back from C, which sleeps in between */
value jp_twice(value f)
{
  caml_callback(f, Val_int(1));
  emscripten_sleep(1);
  caml_callback(f, Val_int(2));
  return Val_unit;
}
