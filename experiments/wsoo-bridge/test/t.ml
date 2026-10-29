type counter
type rect = { w : float; h : float }
type shape = Circle of float | Poly of (int * int) list | Empty

external add : int -> int -> int = "t_add"
external pair : string -> float -> string * float = "t_pair"
external sum : int list -> int = "t_sum"
external range : int -> int list = "t_range"
external fail : string -> unit = "t_fail"
external invalid : unit -> unit = "t_invalid"
external counter_new : int -> counter = "t_counter_new"
external counter_incr : counter -> int = "t_counter_incr"
external fill : bytes -> char -> unit = "t_fill"
external apply : (int -> int) -> int -> int = "t_apply"
external apply2 : (int -> int -> int) -> int -> int -> int = "t_apply2"
external mul64 : int64 -> int64 -> int64 = "t_mul64"
external area : rect -> float = "t_area"
external describe : shape -> string = "t_describe"
external six : int -> int -> int -> int -> int -> int -> int = "t_six_byte" "t_six"
external raise_named : int -> unit = "t_raise_named"

exception Mine of int

let () =
  Printf.printf "add %d\n" (add 40 2);
  let s, f = pair "pi" 3.14 in Printf.printf "pair %s %g\n" s f;
  Printf.printf "sum %d\n" (sum [1; 2; 3; 4]);
  Printf.printf "range %s\n" (String.concat "," (List.map string_of_int (range 5)));
  (try fail "boom" with Failure m -> Printf.printf "Failure %s\n" m);
  (try invalid () with Invalid_argument m -> Printf.printf "Invalid_argument %s\n" m);
  let c = counter_new 10 in
  ignore (counter_incr c); Printf.printf "counter %d\n" (counter_incr c);
  let b = Bytes.make 4 'a' in fill b 'z'; Printf.printf "fill %s\n" (Bytes.to_string b);
  Printf.printf "apply %d\n" (apply (fun x -> x * 3) 7);
  Printf.printf "apply2 %d\n" (apply2 (fun x y -> x - y) 10 3);
  (try ignore (apply (fun _ -> raise (Mine 5)) 1) with Mine n -> Printf.printf "Mine %d through C\n" n);
  Printf.printf "mul64 %Ld\n" (mul64 123456789L 1000L);
  Printf.printf "area %g\n" (area { w = 2.; h = 3.5 });
  List.iter (fun s -> print_endline (describe s)) [Circle 1.5; Poly [1,2; 3,4]; Empty];
  Printf.printf "six %d\n" (six 1 2 3 4 5 6);
  Callback.register_exception "t_mine" (Mine 0);
  (try raise_named 9 with Mine n -> Printf.printf "named Mine %d\n" n);
  let r = ref 0 in for i = 1 to 1_000_000 do r := add !r i land 0xffff done;
  Printf.printf "1M calls: %d\n" !r
