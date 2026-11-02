(* Domains (OCaml >= 5.3): parallel work, Atomic, Mutex across domains,
   minor and major collections while several domains allocate *)

let fib_list n = List.init n (fun i -> let rec fib k = if k < 2 then k else fib (k - 1) + fib (k - 2) in fib (i mod 25))

let () =
  let hits = Atomic.make 0 in
  let m = Mutex.create () and shared = ref [] in
  let work d () =
    let s = List.fold_left ( + ) 0 (fib_list 3000) in
    for _ = 1 to 10_000 do Atomic.incr hits done;
    (* allocation: the domains collect together *)
    let l = List.init 100_000 (fun i -> (i, string_of_int i)) in
    Mutex.lock m;
    shared := (d, List.length l) :: !shared;
    Mutex.unlock m;
    s + d
  in
  let ds = List.init 3 (fun d -> Domain.spawn (work d)) in
  let mine = work 3 () in
  let theirs = List.map Domain.join ds in
  Gc.full_major ();
  Printf.printf "results %s %d, hits %d, shared %s\n"
    (String.concat " " (List.map string_of_int theirs)) mine (Atomic.get hits)
    (String.concat " " (List.map (fun (d, n) -> Printf.sprintf "%d:%d" d n) (List.sort compare !shared)))

(* domain-local state, and a thread inside a domain *)
let key = Domain.DLS.new_key (fun () -> 0)

let () =
  let d =
    Domain.spawn (fun () ->
        Domain.DLS.set key 42;
        let t = Thread.create (fun () -> Domain.DLS.get key) () in
        Thread.join t;
        Domain.DLS.get key)
  in
  Printf.printf "dls: here %d, there %d\n" (Domain.DLS.get key) (Domain.join d);
  (* an exception raised in a domain comes back by join *)
  match Domain.join (Domain.spawn (fun () -> failwith "in a domain")) with
  | () -> print_endline "no exception"
  | exception Failure m -> print_endline ("exception: " ^ m)
