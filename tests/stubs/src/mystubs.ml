external add_int64 : int64 -> int64 -> int64 = "ml_add_int64"
external sum_floats : float array -> float = "ml_sum_floats"
external greeting : unit -> string = "ml_greeting"
external apply_twice : (int -> int) -> int -> int = "ml_apply_twice"
external fail_if_negative : int -> int = "ml_fail_if_negative"
external word_size : unit -> int = "ml_word_size"
type counter
external counter_make : int -> counter = "ml_counter_make"
external counter_incr : counter -> int = "ml_counter_incr"
