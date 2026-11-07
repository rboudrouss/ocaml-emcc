/* Linked in every plugin (`ocaml-emcc plugin`): the address of its entry,
 * camlc_plugin_init, as data, which dynlink.c reads.
 *
 * Looked up with dlsym, the function itself would get a new slot in the
 * table of the thread that looks it up (emscripten's addFunction: it is in
 * none, its address being taken nowhere), which the other threads only add
 * later, when they catch up.  Their tables, and so the place of the next
 * plugin in them, then disagree: with threads, on wasm64, a later load
 * aborted ("table index is out of bounds").  Taken here, its address is in
 * the plugin's own part of the table, the same in every thread. */

typedef void *(*ocaml_emcc_plugin_init)(void);
extern void *camlc_plugin_init(void);

/* (static: the address taken is the plugin's, an address of another
   function would be the first module's of that name, through the GOT; a
   direct call is the plugin's) */
static void *entry(void) { return camlc_plugin_init(); }

const ocaml_emcc_plugin_init ocaml_emcc_plugin_entry = entry;
