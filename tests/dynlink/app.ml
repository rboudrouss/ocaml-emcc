(* What the program offers its plugins *)
let hooks : (string * (unit -> unit)) list ref = ref []

let register name f = hooks := (name, f) :: !hooks

let run_all () = List.iter (fun (n, f) -> Printf.printf "%s: %!" n; f ()) (List.rev !hooks)

exception Plugin_error of string
