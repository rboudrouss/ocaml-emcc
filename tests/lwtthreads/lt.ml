(* lwt with --threads: its jobs (file operations) run in its pool of
   threads, Lwt_preemptive runs OCaml code in other threads *)
open Lwt.Syntax

let rec fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

let main () =
  let file = "lwt_threads.txt" in
  let* () = Lwt_io.with_file ~mode:Lwt_io.Output file (fun oc ->
    Lwt_list.iter_s (fun i -> Lwt_io.fprintf oc "line %d\n" i) [ 1; 2; 3 ]) in
  (* several jobs at once *)
  let* sizes = Lwt_list.map_p (fun _ -> let* st = Lwt_unix.stat file in Lwt.return st.Unix.st_size) [ 1; 2; 3; 4 ] in
  Printf.printf "sizes: %s\n" (String.concat " " (List.map string_of_int sizes));
  let* lines = Lwt_io.with_file ~mode:Lwt_io.Input file (fun ic -> Lwt_stream.to_list (Lwt_io.read_lines ic)) in
  Printf.printf "read back: %s\n" (String.concat "|" lines);
  let* () = Lwt_unix.unlink file in
  (* OCaml code in other threads, while the main one keeps running timers *)
  let ticks = ref 0 in
  let rec tick () = let* () = Lwt_unix.sleep 0.001 in incr ticks; if !ticks < 5 then tick () else Lwt.return () in
  let* results = Lwt.both (Lwt_list.map_p (fun n -> Lwt_preemptive.detach fib n) [ 20; 21; 22 ]) (tick ()) in
  Printf.printf "preemptive: %s, ticks %d\n" (String.concat " " (List.map string_of_int (fst results))) !ticks;
  Lwt.return ()

let () = Lwt_main.run (main ()); print_endline "done"
