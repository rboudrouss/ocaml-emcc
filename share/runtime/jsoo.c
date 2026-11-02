/* The primitives of js_of_ocaml (Js.Unsafe, Js.string, callbacks...) for
 * programs linked by ocaml-emcc, on top of the emscripten library jsoo.js
 * (see its header for the representation of JavaScript values).  `link`
 * compiles this file in instead of the stubs of the libraries jsoo_runtime
 * and js_of_ocaml, which only abort, and when primitives are implemented
 * in JavaScript files (--js-file, see ocaml_emcc_js_prim). */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <limits.h>
#include <sys/stat.h>
#include <emscripten.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/bigarray.h>
#include <caml/printexc.h>
#include <caml/signals.h>

/* jsoo.js */
extern void ocaml_js_init(double ret, double out, int bits);
extern void ocaml_js_free(int h);
extern int ocaml_js_get(int ot, double ox, int kt, double kx, double kl);
extern int ocaml_js_set(int ot, double ox, int kt, double kx, double kl, int vt, double vx);
extern int ocaml_js_delete(int ot, double ox, int kt, double kx, double kl);
extern int ocaml_js_call(int ft, double fx, int ot, double ox, double p, int n);
extern int ocaml_js_meth_call(int ot, double ox, int kt, double kx, double kl, double p, int n);
extern int ocaml_js_new(int ct, double cx, double p, int n);
extern int ocaml_js_new_arr(int ct, double cx, int at, double ax);
extern int ocaml_js_array(double p, int n);
extern int ocaml_js_new_obj(void);
extern int ocaml_js_length(int t, double x);
extern int ocaml_js_equals(int at, double ax, int bt, double bx);
extern int ocaml_js_strict_equals(int at, double ax, int bt, double bx);
extern int ocaml_js_instanceof(int at, double ax, int ct, double cx);
extern int ocaml_js_typeof(int t, double x);
extern int ocaml_js_truthy(int t, double x);
extern double ocaml_js_number(int t, double x);
extern int ocaml_js_int32(int t, double x);
extern int ocaml_js_float(double d);
extern int ocaml_js_string(double p, int len, int latin1);
extern int ocaml_js_string_length(int t, double x, int latin1);
extern void ocaml_js_string_copy(double p);
extern int ocaml_js_eval(double p, int len, int kind);
extern int ocaml_js_index(int t, double x, int i);
extern int ocaml_js_cb_arg(int i);
extern void ocaml_js_cb_exn(double msg);
extern int ocaml_js_wrap(int kind, int arity, double cell);
extern int ocaml_js_console(void);
extern void ocaml_js_debugger(void);
extern int ocaml_js_html_entities(int t, double x);
extern int ocaml_js_xhr(void);
extern int ocaml_js_promise_wrap(int t, double x);
extern int ocaml_js_promise_unwrap(int t, double x);
extern int ocaml_js_ta_kind(int t, double x);
extern int ocaml_js_ta_create(int kind, double p, int n, int buffer);
extern void ocaml_js_ta_copy(int t, double x, double p);
extern int ocaml_js_ta_bytes(int t, double x);
extern int ocaml_js_prim(double name, double p, int n);
extern int ocaml_js_channel(int t, double x, int input);
extern void ocaml_js_mount(double p, int len, int ft, double fx);

#define ADDR(p) ((double)(uintptr_t)(p))

/* Results passed by jsoo.js (see ocamlJs.ret), and the result of a
   callback: (int32 tag, pad, double x). */
static double ret_slot;
static struct { int32_t tag, pad; double x; } out_slot;
static int initialized;

static void init(void)
{
  if (initialized) return;
  initialized = 1;
  ocaml_js_init(ADDR(&ret_slot), ADDR(&out_slot), (int)(8 * sizeof(value)));
}

/* --------------------------------------------------------- JS values */

#define Handle_val(v) (*(int32_t *)Data_custom_val(v))

/* the handles of constants are negated: never released */
static int handle_of(value v)
{
  int h = Handle_val(v);
  return h < 0 ? -h : h;
}

static void js_finalize(value v) { if (Handle_val(v) > 0) ocaml_js_free(Handle_val(v)); }

static int js_compare(value a, value b)
{
  int ha = handle_of(a), hb = handle_of(b);
  if (ha == hb || ocaml_js_strict_equals(ha, 0, hb, 0)) return 0;
  return ha < hb ? -1 : 1;
}

static struct custom_operations js_ops = {
  "_jsoo_value", js_finalize, js_compare, custom_hash_default,
  custom_serialize_default, custom_deserialize_default,
  custom_compare_ext_default, custom_fixed_length_default
};

/* undefined, null, true, false, globalThis: one block each */
#define CONSTANTS 5
static value constants[CONSTANTS + 1];

static value alloc_handle(int h)
{
  value v = caml_alloc_custom(&js_ops, sizeof(int32_t), 0, 1);
  Handle_val(v) = h;
  return v;
}

static value constant(int h)
{
  if (constants[h] == 0) {
    /* never finalized: not released */
    value v = caml_alloc_custom(&js_ops, sizeof(int32_t), 0, 1);
    Handle_val(v) = -h;
    constants[h] = v;
    caml_register_generational_global_root(&constants[h]);
  }
  return constants[h];
}

/* A root holding v, released by jsoo.js (ocaml_emcc_js_release) when
   JavaScript no longer references it. */
static double new_cell(value v)
{
  value *c = malloc(sizeof(value));
  if (c == NULL) caml_raise_out_of_memory();
  *c = v;
  caml_register_generational_global_root(c);
  return ADDR(c);
}

EMSCRIPTEN_KEEPALIVE void ocaml_emcc_js_release(double cell)
{
  value *c = (value *)(uintptr_t)cell;
  caml_remove_generational_global_root(c);
  free(c);
}

static int is_js(value v)
{
  return Is_block(v) && Tag_val(v) == Custom_tag && Custom_ops_val(v) == &js_ops;
}

/* The pair (tag, x) of an OCaml value given to JavaScript. */
static void to_js(value v, int *t, double *x)
{
  if (Is_long(v)) { *t = 0; *x = (double)Long_val(v); }
  else if (is_js(v)) { *t = handle_of(v); *x = 0; }
  else if (Tag_val(v) == Double_tag) { *t = 0; *x = Double_val(v); }
  else { *t = -1; *x = new_cell(v); }
}

#define JS(v) int v##_t; double v##_x; to_js(v, &v##_t, &v##_x)
#define JSV(v) v##_t, v##_x

static void raise_js(int r) __attribute__((noreturn));

static value of_js(int r)
{
  if (r > 0) return r <= CONSTANTS ? constant(r) : alloc_handle(r);
  if (r == 0) return Val_long((intnat)ret_slot);
  if (r == -1) return *(value *)(uintptr_t)ret_slot;
  raise_js(r);
}

/* An OCaml string of a JavaScript value (String(v)), in UTF-8 or
   Latin-1. */
static value js_to_string(int t, double x, int latin1)
{
  int len = ocaml_js_string_length(t, x, latin1);
  value s = caml_alloc_string(len);
  ocaml_js_string_copy(ADDR(Bytes_val(s)));
  return s;
}

static void raise_js(int r)
{
  if (r == -4) caml_raise_stack_overflow();
  if (r == -3) {
    value *c = (value *)(uintptr_t)ret_slot, e = *c;
    ocaml_emcc_js_release(ret_slot);
    caml_raise(e);
  } else {
    CAMLparam0();
    CAMLlocal1(e);
    int h = (int)ret_slot;
    const value *exn = caml_named_value("jsError");
    e = h <= CONSTANTS ? constant(h) : alloc_handle(h);
    /* an Error: Js_error.Exn, otherwise (or when Js_error is not linked)
       Failure (String(e)), as js_of_ocaml */
    if (exn != NULL && r == -2) caml_raise_with_arg(*exn, e);
    caml_failwith_value(js_to_string(h, 0, 0));
    CAMLnoreturn;
  }
}

#define RESULT(call) of_js(call)

/* A property name: an OCaml string as itself, any other value converted
   by JavaScript. */
#define KEY(k)                                                         \
  int k##_t; double k##_x, k##_l = 0;                                  \
  if (Is_block(k) && Tag_val(k) == String_tag) {                       \
    k##_t = -2; k##_x = ADDR(String_val(k)); k##_l = caml_string_length(k); \
  } else to_js(k, &k##_t, &k##_x)
#define KEYV(k) k##_t, k##_x, k##_l

/* The arguments of a call, from an OCaml array: n pairs in a buffer,
   static for a few of them (jsoo.js reads them before calling anything),
   else malloc'd (freed by free_args). */
struct js_arg { int32_t tag, pad; double x; };
#define STATIC_ARGS 16
static struct js_arg static_args[STATIC_ARGS];

static void free_args(void *p)
{
  if (p != static_args) free(p);
}

static void *js_args(value a, int *n)
{
  mlsize_t len = Wosize_val(a);
  struct js_arg *p;
  if (Is_block(a) && Tag_val(a) == Double_array_tag) len = len * sizeof(value) / sizeof(double);
  if (a == Atom(0)) len = 0;
  p = len <= STATIC_ARGS ? static_args : malloc(len * sizeof(*p));
  if (p == NULL) caml_raise_out_of_memory();
  for (mlsize_t i = 0; i < len; i++) {
    int t; double x;
    if (Tag_val(a) == Double_array_tag) { t = 0; x = Double_flat_field(a, i); }
    else to_js(Field(a, i), &t, &x);
    p[i].tag = t;
    p[i].x = x;
  }
  *n = (int)len;
  return p;
}

/* ------------------------------------------------------- primitives */

CAMLprim value caml_js_get(value o, value k)
{
  init();
  JS(o); KEY(k);
  return RESULT(ocaml_js_get(JSV(o), KEYV(k)));
}

CAMLprim value caml_js_set(value o, value k, value v)
{
  init();
  JS(o); KEY(k); JS(v);
  of_js(ocaml_js_set(JSV(o), KEYV(k), JSV(v)));
  return Val_unit;
}

CAMLprim value caml_js_delete(value o, value k)
{
  init();
  JS(o); KEY(k);
  of_js(ocaml_js_delete(JSV(o), KEYV(k)));
  return Val_unit;
}

static value call(int ft, double fx, int ot, double ox, value args)
{
  int n, r;
  void *p = js_args(args, &n);
  r = ocaml_js_call(ft, fx, ot, ox, ADDR(p), n);
  free_args(p);
  return RESULT(r);
}

CAMLprim value caml_js_call(value f, value o, value args)
{
  init();
  JS(f); JS(o);
  return call(JSV(f), JSV(o), args);
}

CAMLprim value caml_js_fun_call(value f, value args)
{
  init();
  JS(f);
  return call(JSV(f), 1, 0, args);
}

CAMLprim value caml_js_meth_call(value o, value m, value args)
{
  int n, r;
  void *p;
  init();
  JS(o);
  p = js_args(args, &n);
  {
    KEY(m);
    r = ocaml_js_meth_call(JSV(o), KEYV(m), ADDR(p), n);
  }
  free_args(p);
  return RESULT(r);
}

CAMLprim value caml_js_new(value c, value args)
{
  int n, r;
  void *p;
  init();
  JS(c);
  p = js_args(args, &n);
  r = ocaml_js_new(JSV(c), ADDR(p), n);
  free_args(p);
  return RESULT(r);
}

CAMLprim value caml_ojs_new_arr(value c, value a)
{
  init();
  JS(c); JS(a);
  return RESULT(ocaml_js_new_arr(JSV(c), JSV(a)));
}

CAMLprim value caml_js_object(value a)
{
  CAMLparam1(a);
  CAMLlocal1(o);
  init();
  o = of_js(ocaml_js_new_obj());
  for (mlsize_t i = 0; i < Wosize_val(a) && a != Atom(0); i++) {
    value k = Field(Field(a, i), 0), v = Field(Field(a, i), 1);
    JS(o); KEY(k); JS(v);
    of_js(ocaml_js_set(JSV(o), KEYV(k), JSV(v)));
  }
  CAMLreturn(o);
}

CAMLprim value caml_js_equals(value a, value b)
{
  init();
  JS(a); JS(b);
  return Val_bool(ocaml_js_equals(JSV(a), JSV(b)));
}

CAMLprim value caml_js_strict_equals(value a, value b)
{
  init();
  JS(a); JS(b);
  return Val_bool(ocaml_js_strict_equals(JSV(a), JSV(b)));
}

CAMLprim value caml_js_instanceof(value a, value c)
{
  init();
  JS(a); JS(c);
  return Val_bool(ocaml_js_instanceof(JSV(a), JSV(c)));
}

CAMLprim value caml_js_typeof(value v)
{
  init();
  JS(v);
  return RESULT(ocaml_js_typeof(JSV(v)));
}

CAMLprim value caml_js_from_bool(value b)
{
  init();
  return constant(Bool_val(b) ? 3 : 4);
}

CAMLprim value caml_js_to_bool(value v)
{
  init();
  JS(v);
  return Val_bool(ocaml_js_truthy(JSV(v)));
}

CAMLprim value caml_js_from_float(value f)
{
  init();
  return RESULT(ocaml_js_float(Double_val(f)));
}

CAMLprim value caml_js_to_float(value v)
{
  init();
  JS(v);
  return caml_copy_double(ocaml_js_number(JSV(v)));
}

CAMLprim value caml_js_from_int32(value i)
{
  init();
  return RESULT(ocaml_js_float((double)Int32_val(i)));
}

CAMLprim value caml_js_to_int32(value v)
{
  init();
  JS(v);
  return caml_copy_int32(ocaml_js_int32(JSV(v)));
}

CAMLprim value caml_js_from_nativeint(value i)
{
  init();
  return RESULT(ocaml_js_float((double)Nativeint_val(i)));
}

CAMLprim value caml_js_to_nativeint(value v)
{
  init();
  JS(v);
  return caml_copy_nativeint(ocaml_js_int32(JSV(v)));
}

static value js_string(value s, int latin1)
{
  init();
  return RESULT(ocaml_js_string(ADDR(String_val(s)), (int)caml_string_length(s), latin1));
}

CAMLprim value caml_jsstring_of_string(value s) { return js_string(s, 0); }
CAMLprim value caml_js_from_string(value s) { return js_string(s, 0); }
CAMLprim value caml_jsbytes_of_string(value s) { return js_string(s, 1); }

static value string_of_js(value v, int latin1)
{
  init();
  JS(v);
  return js_to_string(JSV(v), latin1);
}

CAMLprim value caml_string_of_jsstring(value v) { return string_of_js(v, 0); }
CAMLprim value caml_js_to_string(value v) { return string_of_js(v, 0); }
CAMLprim value caml_string_of_jsbytes(value v) { return string_of_js(v, 1); }
CAMLprim value caml_js_to_byte_string(value v) { return string_of_js(v, 1); }

CAMLprim value caml_js_from_array(value a)
{
  int n, r;
  void *p;
  init();
  p = js_args(a, &n);
  r = ocaml_js_array(ADDR(p), n);
  free_args(p);
  return RESULT(r);
}

CAMLprim value caml_js_to_array(value v)
{
  CAMLparam1(v);
  CAMLlocal2(a, x);
  int n;
  init();
  {
    JS(v);
    n = ocaml_js_length(JSV(v));
  }
  if (n == 0) CAMLreturn(Atom(0));
  a = caml_alloc(n, 0);
  for (int i = 0; i < n; i++) {
    JS(v);
    x = RESULT(ocaml_js_index(JSV(v), i));
    Store_field(a, i, x);
  }
  CAMLreturn(a);
}

CAMLprim value caml_list_of_js_array(value v)
{
  CAMLparam1(v);
  CAMLlocal3(l, x, c);
  int n;
  init();
  {
    JS(v);
    n = ocaml_js_length(JSV(v));
  }
  l = Val_emptylist;
  for (int i = n - 1; i >= 0; i--) {
    JS(v);
    x = RESULT(ocaml_js_index(JSV(v), i));
    c = caml_alloc_small(2, 0);
    Field(c, 0) = x;
    Field(c, 1) = l;
    l = c;
  }
  CAMLreturn(l);
}

CAMLprim value caml_list_to_js_array(value l)
{
  CAMLparam1(l);
  CAMLlocal2(a, x);
  mlsize_t n = 0, i = 0;
  for (x = l; x != Val_emptylist; x = Field(x, 1)) n++;
  a = n ? caml_alloc(n, 0) : Atom(0);
  for (x = l; x != Val_emptylist; x = Field(x, 1)) Store_field(a, i++, Field(x, 0));
  CAMLreturn(caml_js_from_array(a));
}

CAMLprim value caml_string_of_array(value a)
{
  mlsize_t n = a == Atom(0) ? 0 : Wosize_val(a);
  value s = caml_alloc_string(n);
  for (mlsize_t i = 0; i < n; i++) Bytes_val(s)[i] = (unsigned char)Long_val(Field(a, i));
  return s;
}

CAMLprim value caml_js_pure_expr(value f)
{
  return caml_callback(f, Val_unit);
}

CAMLprim value caml_assume_no_perform(value f)
{
  return caml_callback(f, Val_unit);
}

static value js_eval(value s, int kind)
{
  init();
  return RESULT(ocaml_js_eval(ADDR(String_val(s)), (int)caml_string_length(s), kind));
}

CAMLprim value caml_js_eval_string(value s) { return js_eval(s, 0); }
CAMLprim value caml_js_expr(value s) { return js_eval(s, 1); }
CAMLprim value caml_pure_js_expr(value s) { return js_eval(s, 1); }
CAMLprim value caml_js_var(value s) { return js_eval(s, 2); }
CAMLprim value caml_jsoo_runtime_value(value s) { return js_eval(s, 2); }

/* --------------------------------------------------------- callbacks */

/* Kinds of jsoo.js's wrap: 0 wrap_callback, 1 _arguments, 2 _strict, 3
   _unsafe, 4 wrap_meth_callback, 5 _arguments, 6 _strict, 7 _unsafe.  The
   _unsafe ones take as many arguments as the function: its arity is known
   in compiled mode (Closinfo), not for the bytecode, whose closures have
   arity 0 there: they then take those given, as wrap_callback. */
static value wrap(int kind, int arity, value f)
{
  init();
#ifdef Arity_closinfo
  if ((kind == 3 || kind == 7) && Is_block(f) && (Tag_val(f) == Closure_tag || Tag_val(f) == Infix_tag)) {
    int a = (int)Arity_closinfo(Closinfo_val(f));
    if (a > 0 && kind == 3) { kind = 2; arity = a; }
    else if (a > 1 && kind == 7) { kind = 6; arity = a - 1; }
  }
#endif
  return RESULT(ocaml_js_wrap(kind, arity, new_cell(f)));
}

CAMLprim value caml_js_wrap_callback(value f) { return wrap(0, 0, f); }
CAMLprim value caml_js_wrap_callback_arguments(value f) { return wrap(1, 0, f); }
CAMLprim value caml_js_wrap_callback_strict(value a, value f) { return wrap(2, Int_val(a), f); }
CAMLprim value caml_js_wrap_callback_unsafe(value f) { return wrap(3, 0, f); }
CAMLprim value caml_js_wrap_meth_callback(value f) { return wrap(4, 0, f); }
CAMLprim value caml_js_wrap_meth_callback_arguments(value f) { return wrap(5, 0, f); }
CAMLprim value caml_js_wrap_meth_callback_strict(value a, value f) { return wrap(6, Int_val(a), f); }
CAMLprim value caml_js_wrap_meth_callback_unsafe(value f) { return wrap(7, 0, f); }

/* Called by a function of ocaml_js_wrap with its n arguments (got with
   ocaml_js_cb_arg): 0, with the result in out_slot, or 1 for an
   exception (its root in out_slot). */
EMSCRIPTEN_KEEPALIVE int ocaml_emcc_js_callback(double cell, int kind, int n)
{
  CAMLparam0();
  CAMLlocal3(f, a, res);
  value *args;
  int t;
  double x;
  f = *(value *)(uintptr_t)cell;
  if (n == 0) res = caml_callback_exn(f, Val_unit);
  else {
    a = caml_alloc(n, 0);
    for (int i = 0; i < n; i++) Store_field(a, i, of_js(ocaml_js_cb_arg(i)));
    args = alloca(n * sizeof(value));
    for (int i = 0; i < n; i++) args[i] = Field(a, i);
    res = caml_callbackN_exn(f, n, args);
  }
  if (Is_exception_result(res)) {
    char *msg;
    res = Extract_exception(res);
    msg = caml_format_exception(res);
    ocaml_js_cb_exn(ADDR(msg));
    caml_stat_free(msg);
    out_slot.tag = -1;
    out_slot.x = new_cell(res);
    CAMLreturnT(int, 1);
  }
  /* a function returned (partial application) is a callback too */
  if ((kind == 0 || kind == 4) && Is_block(res) && Tag_val(res) == Closure_tag) {
    out_slot.tag = ocaml_js_wrap(0, 0, new_cell(res));
    out_slot.x = 0;
  } else {
    to_js(res, &t, &x);
    out_slot.tag = t;
    out_slot.x = x;
  }
  CAMLreturnT(int, 0);
}

/* ------------------------------------------------------ errors */

static int is_js_error(value exn)
{
  const value *e = caml_named_value("jsError");
  return e != NULL && Is_block(exn) && Tag_val(exn) == 0 && Wosize_val(exn) == 2 && Field(exn, 0) == *e;
}

CAMLprim value caml_js_error_of_exception(value exn)
{
  if (is_js_error(exn)) return Field(exn, 1);
  init();
  return constant(2);
}

CAMLprim value caml_js_error_option_of_exception(value exn)
{
  value r;
  if (!is_js_error(exn)) return Val_int(0);
  r = caml_alloc_small(1, 0);
  Field(r, 0) = Field(exn, 1);
  return r;
}

CAMLprim value caml_exn_with_js_backtrace(value exn, value force)
{
  (void)force;
  return exn;
}

CAMLprim value caml_throw_js_exception(value e)
{
  const value *exn = caml_named_value("jsError");
  if (exn != NULL) caml_raise_with_arg(*exn, e);
  caml_failwith("Js_error.raise_");
}

/* ---------------------------------------------------- miscellaneous */

CAMLprim value caml_js_get_console(value unit)
{
  (void)unit;
  init();
  return RESULT(ocaml_js_console());
}

CAMLprim value debugger(value unit)
{
  (void)unit;
  ocaml_js_debugger();
  return Val_unit;
}

CAMLprim value caml_js_html_entities(value s)
{
  init();
  JS(s);
  return RESULT(ocaml_js_html_entities(JSV(s)));
}

CAMLprim value caml_xmlhttprequest_create(value unit)
{
  int r;
  (void)unit;
  init();
  r = ocaml_js_xhr();
  if (r == 0) caml_failwith("XMLHttpRequest is not available");
  return RESULT(r);
}

CAMLprim value caml_jsoo_promise_wrap(value v)
{
  init();
  JS(v);
  return RESULT(ocaml_js_promise_wrap(JSV(v)));
}

CAMLprim value caml_jsoo_promise_unwrap(value v)
{
  init();
  JS(v);
  return RESULT(ocaml_js_promise_unwrap(JSV(v)));
}

CAMLprim value caml_custom_identifier(value v)
{
  return caml_copy_string(Custom_ops_val(v)->identifier);
}

CAMLprim value caml_jsoo_flags_use_js_string(value unit) { (void)unit; return Val_false; }
CAMLprim value caml_jsoo_flags_effects(value unit) { (void)unit; return caml_copy_string("disabled"); }
CAMLprim value caml_jsoo_build_config(value unit) { (void)unit; return caml_copy_string(""); }

CAMLprim value caml_int64_create_lo_mi_hi(value lo, value mi, value hi)
{
  uint64_t r = ((uint64_t)(Long_val(hi) & 0xffff) << 48) | ((uint64_t)(Long_val(mi) & 0xffffff) << 24)
               | (uint64_t)(Long_val(lo) & 0xffffff);
  return caml_copy_int64((int64_t)r);
}

/* Sys_js: files of emscripten's file system */

static void file_error(value name)
{
  char buf[512];
  snprintf(buf, sizeof buf, "%s: %s", String_val(name), strerror(errno));
  caml_raise_sys_error(caml_copy_string(buf));
}

CAMLprim value caml_create_file(value name, value content)
{
  /* (its directories too, as js_of_ocaml's) */
  char dir[PATH_MAX];
  snprintf(dir, sizeof dir, "%s", String_val(name));
  for (char *p = dir + 1; (p = strchr(p, '/')) != NULL; p++) {
    *p = 0;
    mkdir(dir, 0777);
    *p = '/';
  }
  FILE *f = fopen(String_val(name), "wb");
  if (f == NULL) file_error(name);
  fwrite(String_val(content), 1, caml_string_length(content), f);
  fclose(f);
  return Val_unit;
}

CAMLprim value caml_read_file_content(value name)
{
  CAMLparam1(name);
  CAMLlocal1(s);
  FILE *f = fopen(String_val(name), "rb");
  long n;
  if (f == NULL) file_error(name);
  fseek(f, 0, SEEK_END);
  n = ftell(f);
  fseek(f, 0, SEEK_SET);
  s = caml_alloc_string(n < 0 ? 0 : n);
  if (n > 0 && fread(Bytes_val(s), 1, n, f) != (size_t)n) { fclose(f); file_error(name); }
  fclose(f);
  CAMLreturn(s);
}

/* Sys_js.set_channel_flusher and set_channel_filler: the channel's
   descriptor becomes a device of emscripten's file system calling the
   JavaScript function (jsoo.js), with the bytes written or for bytes to
   read.  Sys_js.mount: a missing file under the path is asked for to the
   function.  Both run OCaml from a system call, which the runtime makes
   in a blocking section (caml_write_fd, caml_read_fd, caml_sys_open...)
   or not (a C library's fopen): the hooks of blocking sections tell, and
   OCaml then runs with the runtime again. */

/* (internals of the runtime, caml/signals.h and caml/io.h: the hooks, and
   the descriptor of a channel, the first field of its struct channel) */
CAMLextern void (*caml_enter_blocking_section_hook)(void);
CAMLextern void (*caml_leave_blocking_section_hook)(void);
#define Channel_fd(v) (**(int **)Data_custom_val(v))

static _Thread_local int blocking;
static void (*prev_enter_hook)(void), (*prev_leave_hook)(void);
static void enter_hook(void) { prev_enter_hook(); blocking = 1; }
static void leave_hook(void) { blocking = 0; prev_leave_hook(); }

/* (once the threads library, which sets the hooks, is initialized) */
static void track_blocking(void)
{
  if (prev_enter_hook) return;
  prev_enter_hook = caml_enter_blocking_section_hook;
  prev_leave_hook = caml_leave_blocking_section_hook;
  caml_enter_blocking_section_hook = enter_hook;
  caml_leave_blocking_section_hook = leave_hook;
}

EMSCRIPTEN_KEEPALIVE int ocaml_emcc_js_runtime_enter(void)
{
  if (!blocking) return 0;
  caml_leave_blocking_section();
  return 1;
}

EMSCRIPTEN_KEEPALIVE void ocaml_emcc_js_runtime_exit(int was_blocking)
{
  if (was_blocking) caml_enter_blocking_section_no_pending();
}

/* The bytes of the OCaml string at cell, or of its option (-1: None) */
EMSCRIPTEN_KEEPALIVE int ocaml_emcc_js_bytes(double cell)
{
  value v = *(value *)(uintptr_t)cell;
  if (Is_long(v)) return -1;
  if (Tag_val(v) != String_tag) v = Field(v, 0);
  ret_slot = ADDR(String_val(v));
  return caml_string_length(v);
}

/* A root of a new OCaml string (the arguments of a mount's function) */
EMSCRIPTEN_KEEPALIVE double ocaml_emcc_js_new_string(double p, int len)
{
  return new_cell(caml_alloc_initialized_string(len, (const char *)(uintptr_t)p));
}

extern value caml_ml_flush(value chan);

static void set_channel(value chan, value f, int input)
{
  JS(f);
  init();
  track_blocking();
  if (!input) caml_ml_flush(chan);
  int fd = ocaml_js_channel(JSV(f), input);
  if (fd < 0) caml_failwith("Sys_js: cannot redirect the channel");
  Channel_fd(chan) = fd;
}

CAMLprim value caml_ml_set_channel_output(value chan, value f)
{
  set_channel(chan, f, 0);
  return Val_unit;
}

CAMLprim value caml_ml_set_channel_refill(value chan, value f)
{
  set_channel(chan, f, 1);
  return Val_unit;
}

/* the mounted paths, ending with a slash (as js_of_ocaml's) */
static value mounts = Val_emptylist;

static value with_slash(value path)
{
  mlsize_t n = caml_string_length(path);
  if (n > 0 && String_val(path)[n - 1] == '/') return path;
  value s = caml_alloc_string(n + 1);
  memcpy(Bytes_val(s), String_val(path), n);
  Bytes_val(s)[n] = '/';
  return s;
}

CAMLprim value caml_mount_autoload(value path, value f)
{
  CAMLparam2(path, f);
  CAMLlocal1(cell);
  JS(f);
  init();
  track_blocking();
  ocaml_js_mount(ADDR(String_val(path)), caml_string_length(path), JSV(f));
  if (mounts == Val_emptylist) caml_register_generational_global_root(&mounts);
  path = with_slash(path);
  cell = caml_alloc_small(2, Tag_cons);
  Field(cell, 0) = path;
  Field(cell, 1) = mounts;
  caml_modify_generational_global_root(&mounts, cell);
  CAMLreturn(Val_unit);
}

CAMLprim value caml_unmount(value path)
{
  CAMLparam1(path);
  CAMLlocal3(l, kept, cell);
  init();
  ocaml_js_mount(ADDR(String_val(path)), caml_string_length(path), 0, 0);
  path = with_slash(path);
  for (l = mounts; l != Val_emptylist; l = Field(l, 1))
    if (caml_string_length(Field(l, 0)) != caml_string_length(path)
        || memcmp(String_val(Field(l, 0)), String_val(path), caml_string_length(path))) {
      cell = caml_alloc_small(2, Tag_cons);
      Field(cell, 0) = Field(l, 0);
      Field(cell, 1) = kept;
      kept = cell;
    }
  if (mounts != Val_emptylist) caml_modify_generational_global_root(&mounts, kept);
  CAMLreturn(Val_unit);
}

CAMLprim value caml_list_mount_point(value unit)
{
  (void)unit;
  return mounts;
}

/* Typed arrays: copies, the wasm memory moves when it grows */

static const int ta_kinds[] = {
  CAML_BA_FLOAT32, CAML_BA_FLOAT64, CAML_BA_SINT8, CAML_BA_UINT8,
  CAML_BA_SINT16, CAML_BA_UINT16, CAML_BA_INT32, CAML_BA_INT64
};

/* the sizes of the elements of each kind (caml_ba_element_size is
   internal) */
static const int ba_element_size[] = { 4, 8, 1, 1, 2, 2, 4, 8, sizeof(value), sizeof(value), 8, 16, 1, 2 };

static int ta_kind_of_ba(int kind)
{
  for (int i = 0; i < 8; i++) if (ta_kinds[i] == kind) return i;
  caml_invalid_argument("Typed_array: unsupported bigarray kind");
}

CAMLprim value caml_ba_kind_of_typed_array(value v)
{
  int k;
  init();
  JS(v);
  k = ocaml_js_ta_kind(JSV(v));
  if (k < 0) caml_invalid_argument("caml_ba_kind_of_typed_array");
  return Val_int(ta_kinds[k]);
}

static value ba_to_js(value ba, int as_uint8, int buffer)
{
  struct caml_ba_array *b = Caml_ba_array_val(ba);
  int k = as_uint8 ? 3 : ta_kind_of_ba(b->flags & CAML_BA_KIND_MASK);
  uintnat n = 1;
  for (int i = 0; i < b->num_dims; i++) n *= b->dim[i];
  if (as_uint8) n *= ba_element_size[b->flags & CAML_BA_KIND_MASK];
  init();
  return RESULT(ocaml_js_ta_create(k, ADDR(b->data), (int)n, buffer));
}

CAMLprim value caml_ba_to_typed_array(value ba) { return ba_to_js(ba, 0, 0); }
CAMLprim value bigstring_to_typed_array(value ba) { return ba_to_js(ba, 1, 0); }
CAMLprim value bigstring_to_array_buffer(value ba) { return ba_to_js(ba, 1, 1); }

static value ba_of_js(value v, int kind)
{
  CAMLparam1(v);
  CAMLlocal1(ba);
  intnat dim;
  int bytes;
  init();
  {
    JS(v);
    if (kind < 0) {
      int k = ocaml_js_ta_kind(JSV(v));
      if (k < 0) caml_invalid_argument("Typed_array.to_genarray");
      kind = ta_kinds[k];
    }
    bytes = ocaml_js_ta_bytes(JSV(v));
  }
  dim = bytes / ba_element_size[kind];
  ba = caml_ba_alloc(kind | CAML_BA_C_LAYOUT, 1, NULL, &dim);
  {
    JS(v);
    ocaml_js_ta_copy(JSV(v), ADDR(Caml_ba_data_val(ba)));
  }
  CAMLreturn(ba);
}

CAMLprim value caml_ba_from_typed_array(value v) { return ba_of_js(v, -1); }
CAMLprim value bigstring_of_typed_array(value v) { return ba_of_js(v, CAML_BA_UINT8); }
CAMLprim value bigstring_of_array_buffer(value v) { return ba_of_js(v, CAML_BA_UINT8); }

CAMLprim value caml_string_of_uint8_array(value v)
{
  CAMLparam1(v);
  CAMLlocal1(s);
  int n;
  init();
  {
    JS(v);
    n = ocaml_js_ta_bytes(JSV(v));
  }
  s = caml_alloc_string(n);
  {
    JS(v);
    ocaml_js_ta_copy(JSV(v), ADDR(Bytes_val(s)));
  }
  CAMLreturn(s);
}

CAMLprim value caml_bytes_of_uint8_array(value v) { return caml_string_of_uint8_array(v); }

CAMLprim value caml_uint8_array_of_bytes(value s)
{
  init();
  return RESULT(ocaml_js_ta_create(3, ADDR(Bytes_val(s)), (int)caml_string_length(s), 0));
}

/* ------------------------------------------- primitives in JavaScript */

/* The primitive NAME implemented by a function of a --js-file, called by
   the stubs `link` generates for it: the function gets the n arguments as
   JavaScript values, and its result is converted back. */
value ocaml_emcc_js_prim(const char *name, int n, value *args)
{
  int r;
  void *p;
  struct js_arg *a;
  init();
  a = p = n <= STATIC_ARGS ? static_args : malloc(n * sizeof(*a));
  if (p == NULL) caml_raise_out_of_memory();
  for (int i = 0; i < n; i++) {
    int t;
    double x;
    to_js(args[i], &t, &x);
    a[i].tag = t;
    a[i].x = x;
  }
  r = ocaml_js_prim(ADDR(name), ADDR(p), n);
  free_args(p);
  return RESULT(r);
}
