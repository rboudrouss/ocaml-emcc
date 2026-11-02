external loadfile : string -> unit = "caml_emcc_dynlink_loadfile"

external open_async : string -> ((nativeint, string) result -> unit) -> unit = "caml_emcc_dynlink_open_async"

external run : nativeint -> unit = "caml_emcc_dynlink_run"

let load_url url k =
  open_async url (function
    | Error msg -> k (Error (Failure ("Emcc_dynlink.load_url " ^ url ^ ": " ^ msg)))
    | Ok h -> k (match run h with () -> Ok () | exception e -> Error e))
