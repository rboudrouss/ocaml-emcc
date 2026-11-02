(* An effect of the program, handled by the program, performed by plugins *)
type _ Effect.t += Ask : string -> int Effect.t

let hooks : (unit -> unit) list ref = ref []

let register f = hooks := f :: !hooks

let with_answers f =
  Effect.Deep.match_with f ()
    {
      retc = Fun.id;
      exnc = raise;
      effc =
        (fun (type a) (e : a Effect.t) ->
          match e with
          | Ask s -> Some (fun (k : (a, _) Effect.Deep.continuation) -> Effect.Deep.continue k (String.length s))
          | _ -> None);
    }
