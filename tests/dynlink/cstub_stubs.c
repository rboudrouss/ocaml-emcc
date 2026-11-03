/* the C of a plugin: its data (relocated when loaded), the runtime's
   functions (the program's) */
#include <caml/mlvalues.h>
#include <caml/alloc.h>

static int calls;
static const char *names[] = { "zero", "one", "two" };

value plug_count(value n)
{
  calls++;
  return Val_int(Int_val(n) * 10 + calls);
}

value plug_tag(value s)
{
  return caml_alloc_sprintf("%s-%s", String_val(s), names[calls % 3]);
}
