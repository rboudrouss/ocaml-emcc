(** Loading plugins in programs compiled by ocaml-emcc.

    A plugin is an OCaml library ([.cma]) or module ([.cmo]) compiled to a
    wasm side module by [ocaml-emcc plugin], loaded by a program linked with
    [ocaml-emcc build/link --dynlink] from bytecode linked with
    [-linkall]. Loading a plugin runs the initialization of its modules,
    which can use those of the program and of the plugins loaded before
    it. *)

val loadfile : string -> unit
(** [loadfile file] loads the plugin [file] and runs it. The file is read in
    the file system of the program (emscripten's, or the real one under
    node with [--node-fs]). In a web page, use {!load_url} instead.

    @raise Failure if the file is not a plugin, uses a module that is not
    loaded, or defines one already loaded; any exception its initialization
    raises. *)

val load_url : string -> ((unit, exn) result -> unit) -> unit
(** [load_url url k] fetches the plugin at [url] (in a web page; a file
    under node), loads it and runs it, then calls [k] with [Ok ()] or
    [Error e], [e] being the exception {!loadfile} would raise. [k] is called
    later, from the event loop: the program keeps running until then. *)
