external sqrt_dec : string -> int -> string = "depgraph_sqrt"
external versions : unit -> string = "depgraph_versions"

(** [sqrt z n]: the square root of [z] with [n] significant digits. *)
let sqrt z n = sqrt_dec (Z.to_string z) n
