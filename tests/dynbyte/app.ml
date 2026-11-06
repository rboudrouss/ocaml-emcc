(* What the plugins register *)
let hooks : (string -> string) list ref = ref []
let register f = hooks := f :: !hooks
