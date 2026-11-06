(* A second plugin, using the first *)
let () = App.register (fun n -> P.scale * n)
