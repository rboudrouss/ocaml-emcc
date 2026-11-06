(* What the plugin registers, and a counter its threads share with the
   program's *)
let hooks : (int -> int) list ref = ref []
let register f = hooks := f :: !hooks
let m = Mutex.create ()
let total = ref 0
let add n = Mutex.lock m; total := !total + n; Mutex.unlock m
