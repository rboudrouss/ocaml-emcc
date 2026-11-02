(* A plugin using the program, the standard library and str *)
let squares = List.init 6 (fun i -> i * i)

let () =
  App.register "a" (fun () ->
      let t = Hashtbl.create 8 in
      List.iter (fun x -> Hashtbl.replace t x (string_of_int x)) squares;
      Printf.printf "%s | %s\n" (String.concat "," (List.map (Hashtbl.find t) squares))
        (String.concat "+" (Str.split (Str.regexp "[ ]+") "split  by   str")))
