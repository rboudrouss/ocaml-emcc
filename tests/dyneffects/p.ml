(* Effects performed under the program's handler, through List.fold_left
   (code of the program), and an effect handled by the plugin itself *)
type _ Effect.t += Twice : int -> int Effect.t

let twice f =
  Effect.Deep.try_with f ()
    {
      effc =
        (fun (type a) (e : a Effect.t) ->
          match e with
          | Twice n -> Some (fun (k : (a, _) Effect.Deep.continuation) -> Effect.Deep.continue k (2 * n))
          | _ -> None);
    }

let () =
  App.register (fun () ->
      let n = List.fold_left (fun acc s -> acc + Effect.perform (App.Ask s)) 0 [ "a"; "bb"; "ccc" ] in
      Printf.printf "asked: %d\n" n;
      Printf.printf "twice: %d\n" (twice (fun () -> Effect.perform (Twice 21) + Effect.perform (App.Ask "xyz"))))
