/* Stubs over cJSON.  The library only exists for the wasm target (built by
   the project recipe emcc-recipes/cjson), so the prototypes are declared
   here: the host build of the bytecode only needs these to compile. */
#include <stddef.h>
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>

typedef struct cJSON cJSON;
extern cJSON *cJSON_Parse(const char *);
extern cJSON *cJSON_GetObjectItemCaseSensitive(const cJSON *, const char *);
extern double cJSON_GetNumberValue(const cJSON *);
extern char *cJSON_GetStringValue(const cJSON *);
extern int cJSON_GetArraySize(const cJSON *);
extern char *cJSON_PrintUnformatted(const cJSON *);
extern const char *cJSON_Version(void);
extern void cJSON_Delete(cJSON *);
extern void cJSON_free(void *);

value ml_cjson_version(value unit) { return caml_copy_string(cJSON_Version()); }

/* (string field, number field, array field length, reprinted json) */
value ml_cjson_inspect(value json, value sfield, value nfield, value afield)
{
  CAMLparam4(json, sfield, nfield, afield);
  CAMLlocal2(res, s);
  cJSON *root = cJSON_Parse(String_val(json));
  if (root == NULL) caml_failwith("cJSON_Parse");
  char *str = cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(root, String_val(sfield)));
  double num = cJSON_GetNumberValue(cJSON_GetObjectItemCaseSensitive(root, String_val(nfield)));
  int len = cJSON_GetArraySize(cJSON_GetObjectItemCaseSensitive(root, String_val(afield)));
  char *printed = cJSON_PrintUnformatted(root);
  res = caml_alloc_tuple(4);
  s = caml_copy_string(str ? str : "(null)"); Store_field(res, 0, s);
  s = caml_copy_double(num); Store_field(res, 1, s);
  Store_field(res, 2, Val_int(len));
  s = caml_copy_string(printed); Store_field(res, 3, s);
  cJSON_free(printed);
  cJSON_Delete(root);
  CAMLreturn(res);
}
