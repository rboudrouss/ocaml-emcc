(* a plugin with C stubs of its own (cstub_stubs.c, in libcstub_stubs.a) *)
external count : int -> int = "plug_count"
external tag : string -> string = "plug_tag"

let () =
  App.register "cstub" (fun () ->
      let a = count 6 in
      let b = count 7 in
      Printf.printf "%d %d %s\n" a b (tag "c"))
