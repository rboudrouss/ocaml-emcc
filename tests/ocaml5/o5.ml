(* OCaml 5 specific features on the emscripten runtime. *)
open Effect
open Effect.Deep

type _ Effect.t += Ask : int Effect.t | Yield : int -> unit Effect.t

let step name f = Printf.printf "%-28s%!" name; (try f () with e -> Printf.printf "EXN %s" (Printexc.to_string e)); print_newline ()

let () =
  step "effects: handler" (fun () ->
      let r = match_with (fun () -> perform Ask + perform Ask) () { retc = Fun.id; exnc = raise;
        effc = (fun (type a) (e : a t) -> match e with Ask -> Some (fun (k : (a, _) continuation) -> continue k 21) | _ -> None) } in
      Printf.printf "%d" r);
  step "effects: generator" (fun () ->
      let items = ref [] in
      try_with (fun () -> for i = 1 to 5 do perform (Yield i) done) ()
        { effc = (fun (type a) (e : a t) -> match e with
            | Yield n -> Some (fun (k : (a, _) continuation) -> items := n :: !items; continue k ())
            | _ -> None) };
      Printf.printf "%s" (String.concat "," (List.rev_map string_of_int !items)));
  step "effects: deep recursion" (fun () ->
      let rec loop n = if n = 0 then 0 else perform Ask + loop (n - 1) in
      let r = match_with loop 100_000 { retc = Fun.id; exnc = raise;
        effc = (fun (type a) (e : a t) -> match e with Ask -> Some (fun (k : (a, _) continuation) -> continue k 1) | _ -> None) } in
      Printf.printf "%d" r);
  step "unhandled effect" (fun () -> ignore (perform Ask));
  step "Atomic" (fun () -> let a = Atomic.make 0 in for _ = 1 to 1000 do Atomic.incr a done; Printf.printf "%d" (Atomic.get a));
  step "Mutex" (fun () -> let m = Mutex.create () in Mutex.lock m; print_string "ok"; Mutex.unlock m);
  step "Dynarray" Dynarray_step.run;
  step "Domain.recommended_count" (fun () -> Printf.printf "%d" (Domain.recommended_domain_count ()));
  step "Domain.spawn" (fun () -> let d = Domain.spawn (fun () -> 6 * 7) in Printf.printf "%d" (Domain.join d));
  step "Gc" (fun () -> Gc.full_major (); Printf.printf "ok")
