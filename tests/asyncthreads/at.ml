(* async with --threads: In_thread.run runs its jobs in threads, several at once *)
open Core
open Async

let main () =
  let started = Time_ns.now () in
  let%bind l =
    Deferred.List.map ~how:`Parallel [ 1; 2; 3; 4 ] ~f:(fun i ->
        In_thread.run (fun () ->
            Core_unix.sleep 1;
            i * 10))
  in
  let elapsed = Time_ns.diff (Time_ns.now ()) started in
  printf "results %s\n" (Sexp.to_string [%sexp (l : int list)]);
  printf "in parallel (< 3 s): %b\n" Time_ns.Span.(elapsed < of_sec 3.);
  let%bind () = Writer.flushed (force Writer.stdout) in
  return ()

let () =
  don't_wait_for (let%map () = main () in shutdown 0);
  never_returns (Scheduler.go ())
