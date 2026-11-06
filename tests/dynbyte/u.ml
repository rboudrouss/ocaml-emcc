let () = App.register (fun s -> "u:" ^ Str.global_replace (Str.regexp "x") "y" s)
