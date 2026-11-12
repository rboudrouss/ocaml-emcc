(** Symbolic values and checks for owi, OCamlPro's symbolic execution engine
    for wasm, in a program linked by [ocaml-emcc link --owi].

    owi runs the program on symbolic values: each path it takes gives
    constraints on them, and it reports the values that make the program
    fail (an exception not caught, a failed {!check}, a trap of the C code)
    with the path that leads there.

    Outside of owi (a native program), every value is 0, [assume false]
    exits with code 0 and [check false] aborts. *)

val int : unit -> int
(** A symbolic integer, of 32 bits (sign extended; on wasm32, an OCaml int
    has 31). *)

val int64 : unit -> int64

val bool : unit -> bool

val char : unit -> char

val string : int -> string
(** [string n]: [n] symbolic characters. *)

val assume : bool -> unit
(** [assume c]: the paths where [c] is false are dropped (not reported). *)

val check : bool -> unit
(** [check c]: owi reports the values that make [c] false. *)
