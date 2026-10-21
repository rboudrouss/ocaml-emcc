let () =
  Printf.printf "C word size = Sys.word_size: %b\n" (Mystubs.word_size () = Sys.word_size);
  Printf.printf "add_int64: %Ld\n" (Mystubs.add_int64 4000000000L 5000000000L);
  Printf.printf "sum_floats: %g\n" (Mystubs.sum_floats [| 1.5; 2.25; 3.125 |]);
  Printf.printf "greeting: %s\n" (Mystubs.greeting ());
  Printf.printf "apply_twice: %d\n" (Mystubs.apply_twice (fun x -> x * 10 + 1) 4);
  (try ignore (Mystubs.fail_if_negative (-1)) with Failure m -> Printf.printf "C raised Failure %S\n" m);
  let c = Mystubs.counter_make 41 in
  Printf.printf "counter: %d\n" (Mystubs.counter_incr c);
  (* unix *)
  let t = Unix.gettimeofday () in
  Printf.printf "unix: gettimeofday > 1e9: %b, getpid > 0: %b\n" (t > 1e9) (Unix.getpid () > 0);
  let fd = Unix.openfile "/tmp/ocaml-emcc-unix.txt" [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
  ignore (Unix.write_substring fd "unix write\n" 0 11);
  Unix.close fd;
  Printf.printf "unix: stat size = %d\n" (Unix.stat "/tmp/ocaml-emcc-unix.txt").Unix.st_size;
  (try ignore (Unix.stat "/nonexistent") with Unix.Unix_error (e, f, _) -> Printf.printf "unix: %s %s\n" f (Unix.error_message e));
  (* str *)
  let re = Str.regexp "\\([a-z]+\\)-\\([0-9]+\\)" in
  if Str.string_match re "ocaml-414" 0 then
    Printf.printf "str: %s / %s\n" (Str.matched_group 1 "ocaml-414") (Str.matched_group 2 "ocaml-414");
  Printf.printf "str: split = [%s]\n" (String.concat "|" (Str.split (Str.regexp ",") "a,b,,c"))
