(* async: the scheduler, a timer, deferreds, a pipe, writers *)
open Core
open Async

let main () =
  let start = Time_ns.now () in
  let%bind () = Clock_ns.after (Time_ns.Span.of_int_ms 20) in
  let elapsed = Time_ns.diff (Time_ns.now ()) start in
  printf "slept >= 20ms: %b\n" Time_ns.Span.(elapsed >= of_int_ms 20);
  let%bind l = Deferred.List.map ~how:`Parallel [ 1; 2; 3 ] ~f:(fun i -> return (i * 2)) in
  printf "list %s\n" (Sexp.to_string [%sexp (l : int list)]);
  let p = Pipe.of_list [ "a"; "b" ] in
  let%bind l = Pipe.to_list p in
  printf "pipe %s\n" (String.concat l);
  let%bind () = Writer.flushed (force Writer.stdout) in
  return ()

let () =
  don't_wait_for (let%map () = main () in shutdown 0);
  never_returns (Scheduler.go ())
