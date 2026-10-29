/* C side of the wasm_of_ocaml <-> emscripten bridge (prototype).

   The OCaml program is compiled by wasm_of_ocaml (Wasm GC values).  Its
   primitives that wasm_of_ocaml does not implement are C stubs, compiled by
   emscripten with a libcamlrun (linear-memory values).  bridge.wat converts
   the arguments of each call into linear-memory values, calls oe_call,
   and converts the result (or the exception) back.

   Values cross through a stack of GC roots (oe_stack): the arguments of a
   call are pushed by bridge.wat, oe_call leaves its result in the first
   slot.  Values allocated while converting go to the major heap
   (caml_alloc_shr), which neither moves them nor collects before the call. */

#define CAML_INTERNALS
#include <string.h>
#include <emscripten.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fix_code.h>
#include <caml/instruct.h>
#include <caml/prims.h>
#include <caml/startup.h>
#include <caml/globroots.h>
#include <caml/codefrag.h>
#include <caml/domain_state.h>
#include <caml/fiber.h>
#include <caml/signals.h>

#define OE_STACK 4096
static value oe_stack[OE_STACK];

EMSCRIPTEN_KEEPALIVE value *oe_stack_base(void) { return oe_stack; }

/* ---- handles: C values kept alive for the GC side ---------------------- */

static value *oe_handles;
static int oe_nhandles, oe_handles_cap, oe_free = -1;

EMSCRIPTEN_KEEPALIVE int oe_handle_new(value v)
{
  int h;
  if (oe_free >= 0) {
    h = oe_free;
    oe_free = Int_val(oe_handles[h]);
    caml_modify_generational_global_root(&oe_handles[h], v);
    return h;
  }
  if (oe_nhandles == oe_handles_cap) {
    /* roots cannot move: register a fresh array, drop the old one */
    int cap = oe_handles_cap ? 2 * oe_handles_cap : 256;
    value *a = malloc(cap * sizeof(value));
    for (int i = 0; i < cap; i++) {
      a[i] = i < oe_nhandles ? oe_handles[i] : Val_unit;
      caml_register_generational_global_root(&a[i]);
    }
    for (int i = 0; i < oe_nhandles; i++)
      caml_remove_generational_global_root(&oe_handles[i]);
    free(oe_handles);
    oe_handles = a; oe_handles_cap = cap;
  }
  h = oe_nhandles++;
  caml_modify_generational_global_root(&oe_handles[h], v);
  return h;
}

EMSCRIPTEN_KEEPALIVE value oe_handle_get(int h) { return oe_handles[h]; }

EMSCRIPTEN_KEEPALIVE void oe_handle_free(int h)
{
  caml_modify_generational_global_root(&oe_handles[h], Val_int(oe_free));
  oe_free = h;
}

/* ---- allocation, for the conversion to C ------------------------------- */

EMSCRIPTEN_KEEPALIVE value oe_alloc(int tag, int wosize)
{
  value v;
  if (wosize == 0) return Atom(tag);
  v = caml_alloc_shr(wosize, tag);
  if (tag < No_scan_tag)
    for (int i = 0; i < wosize; i++) Field(v, i) = Val_unit;
  return v;
}

EMSCRIPTEN_KEEPALIVE void oe_set_field(value b, int i, value v)
{
  caml_initialize(&Field(b, i), v);
}

EMSCRIPTEN_KEEPALIVE value oe_alloc_string(int len)
{
  mlsize_t wosize = (len + sizeof(value)) / sizeof(value);
  value v = caml_alloc_shr(wosize, String_tag);
  mlsize_t offset_index = Bsize_wsize(wosize) - 1;
  Field(v, wosize - 1) = 0;
  Byte(v, offset_index) = offset_index - len;
  return v;
}

EMSCRIPTEN_KEEPALIVE value oe_alloc_double(double d)
{
  value v = caml_alloc_shr(Double_wosize, Double_tag);
  Store_double_val(v, d);
  return v;
}

/* minor heap: stored at once in a field or a stack slot (caml_initialize
   records it), and no other allocation happens before */
EMSCRIPTEN_KEEPALIVE value oe_copy_int64(int64_t i) { return caml_copy_int64(i); }
EMSCRIPTEN_KEEPALIVE value oe_copy_int32(int32_t i) { return caml_copy_int32(i); }
EMSCRIPTEN_KEEPALIVE value oe_copy_nativeint(intnat i) { return caml_copy_nativeint(i); }

/* 0 other, 1 int64, 2 int32, 3 nativeint */
EMSCRIPTEN_KEEPALIVE int oe_custom_kind(value v)
{
  const char *id = Custom_ops_val(v)->identifier;
  if (strcmp(id, "_j") == 0) return 1;
  if (strcmp(id, "_i") == 0) return 2;
  if (strcmp(id, "_n") == 0) return 3;
  return 0;
}

/* ---- OCaml closures of the GC side --------------------------------------

   A closure of the GC side becomes a bytecode closure of one argument
   whose code calls oe_apply_prim(handle, arg): the runtime's caml_callback
   applies it unchanged, an exception it raises goes through the
   interpreter like any other. */

extern value oe_wat_apply(int handle, value arg, int *raised); /* bridge.wat */
extern void oe_wat_release(int handle);

static opcode_t oe_closure_code[] = {
  ACC, 0, PUSHENVACC, 2, C_CALL2, 0 /* patched */, RETURN, 1
};

static value oe_apply_prim(value handle, value arg)
{
  int raised = 0;
  value res = oe_wat_apply(Int_val(handle), arg, &raised);
  if (raised) caml_raise(res);
  return res;
}

EMSCRIPTEN_KEEPALIVE value oe_closure(int handle)
{
  value c = caml_alloc_shr(3, Closure_tag);
  Code_val(c) = (code_t) oe_closure_code;
  Closinfo_val(c) = Make_closinfo(1, 2);
  Field(c, 2) = Val_int(handle);
  return c;
}

/* the handle of a closure made by oe_closure, -1 otherwise */
EMSCRIPTEN_KEEPALIVE int oe_closure_handle(value c)
{
  return Code_val(c) == (code_t) oe_closure_code ? Int_val(Field(c, 2)) : -1;
}

/* ---- calls ------------------------------------------------------------- */

extern value oe_dispatch(int prim, value *args, int argc); /* generated */

/* calls primitive [prim] on the [argc] values at [base]; its result, or
   the exception it raised, goes in the next slot.  Returns 1 if it
   raised. */
EMSCRIPTEN_KEEPALIVE int oe_call(int prim, int base, int argc)
{
  volatile value exn = Val_unit;
  struct longjmp_buffer buf;
  caml_domain_state *st = Caml_state;
  struct caml_exception_context ctx = { &buf, st->local_roots, &exn };
  struct caml_exception_context *saved = st->external_raise;
  value res;
  if (sigsetjmp(buf.buf, 0)) {
    st->external_raise = saved;
    oe_stack[base + argc] = exn;
    return 1;
  }
  st->external_raise = &ctx;
  res = oe_dispatch(prim, &oe_stack[base], argc);
  st->external_raise = saved;
  oe_stack[base + argc] = res;
  /* a safe point, as the interpreter's polls: major slices requested by
     the call (major heap allocations) run here */
  caml_process_pending_actions_exn();
  return 0;
}

/* the predefined exception [i] (caml_global_data), to map it to the GC
   side's */
EMSCRIPTEN_KEEPALIVE value oe_predef_exn(int i) { return Field(caml_global_data, i); }

extern void caml_startup(char_os **argv); /* oeinit.c: an empty program */

EMSCRIPTEN_KEEPALIVE void oe_init(void)
{
  static char_os *argv[] = { "oe", NULL };
  caml_startup(argv);
  for (int i = 0; i < OE_STACK; i++) {
    oe_stack[i] = Val_unit;
    caml_register_generational_global_root(&oe_stack[i]);
  }
  oe_closure_code[5] = caml_prim_table.size;
  caml_ext_table_add(&caml_prim_table, (void *) oe_apply_prim);
  caml_register_code_fragment((char *) oe_closure_code,
                              (char *) oe_closure_code + sizeof(oe_closure_code),
                              DIGEST_IGNORE, NULL);
  caml_thread_code(oe_closure_code, sizeof(oe_closure_code));
}

/* ---- named values: those registered by the OCaml program (Callback) are
   on the GC side ---------------------------------------------------------- */

extern const value *__real_caml_named_value(char const *name);
extern value oe_wat_named_value(const char *name, int len); /* bridge.wat */
extern value caml_register_named_value(value vname, value val);

const value *__wrap_caml_named_value(char const *name)
{
  CAMLparam0();
  CAMLlocal2(v, n);
  const value *r = __real_caml_named_value(name);
  if (r != NULL) CAMLreturnT(const value *, r);
  v = oe_wat_named_value(name, strlen(name));
  if (v == 0) CAMLreturnT(const value *, NULL);
  n = caml_copy_string(name);
  caml_register_named_value(n, v);
  CAMLreturnT(const value *, __real_caml_named_value(name));
}

/* ---- custom operations of C values, for the GC side ---------------------- */

extern value caml_compare(value, value);

EMSCRIPTEN_KEEPALIVE int oe_compare(value a, value b)
{
  return Int_val(caml_compare(a, b));
}

/* what the C custom operations hash (the GC side's caml_hash mixes it as
   the runtime does) */
EMSCRIPTEN_KEEPALIVE int oe_hash(value v)
{
  if (Is_block(v) && Tag_val(v) == Custom_tag && Custom_ops_val(v)->hash != NULL)
    return (int) Custom_ops_val(v)->hash(v);
  return 0;
}

/* a custom block without finalizer is plain data: the GC side copies it */
EMSCRIPTEN_KEEPALIVE int oe_custom_finalized(value v)
{
  return Custom_ops_val(v)->finalize != NULL;
}
