let run () = let d = Dynarray.create () in for i = 1 to 10 do Dynarray.add_last d i done; Printf.printf "%d" (Dynarray.fold_left ( + ) 0 d)
