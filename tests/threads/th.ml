(* Threads: Thread, Mutex, Condition, Event, with real threads (--threads) *)

let counter = ref 0
let m = Mutex.create ()

let worker n () =
  for i = 1 to 10_000 do
    Mutex.lock m;
    counter := !counter + 1;
    Mutex.unlock m;
    if i mod 1000 = 0 then Thread.yield ()
  done;
  n * n

(* results through a mutex-protected table, joined *)
let () =
  let results = Array.make 4 0 in
  let ts = List.init 4 (fun i -> Thread.create (fun () -> results.(i) <- worker i ()) ()) in
  List.iter Thread.join ts;
  Printf.printf "counter %d, results %s\n" !counter
    (String.concat " " (Array.to_list (Array.map string_of_int results)))

(* a bounded queue: producer and consumers with conditions *)
let () =
  let q = Queue.create () and m = Mutex.create () in
  let not_empty = Condition.create () and not_full = Condition.create () in
  let producer () =
    for i = 1 to 1000 do
      Mutex.lock m;
      while Queue.length q >= 10 do Condition.wait not_full m done;
      Queue.push i q;
      Condition.signal not_empty;
      Mutex.unlock m
    done
  in
  let sum = ref 0 and taken = ref 0 in
  let consumer () =
    let continue = ref true in
    while !continue do
      Mutex.lock m;
      while Queue.is_empty q && !taken < 1000 do Condition.wait not_empty m done;
      if !taken >= 1000 then continue := false
      else begin
        sum := !sum + Queue.pop q;
        incr taken;
        if !taken = 1000 then Condition.broadcast not_empty;
        Condition.signal not_full
      end;
      Mutex.unlock m
    done
  in
  let p = Thread.create producer () in
  let cs = List.init 3 (fun _ -> Thread.create consumer ()) in
  Thread.join p;
  List.iter Thread.join cs;
  Printf.printf "queue: %d items, sum %d\n" !taken !sum

(* channels of the Event module *)
let () =
  let c = Event.new_channel () in
  let t = Thread.create (fun () -> for i = 1 to 5 do Event.sync (Event.send c (i * 10)) done) () in
  let got = List.init 5 (fun _ -> Event.sync (Event.receive c)) in
  Thread.join t;
  Printf.printf "event: %s\n" (String.concat " " (List.map string_of_int got))

(* a thread sleeping while the main one waits for it; exceptions in
   threads; Thread.exit *)
let () =
  let flag = ref false in
  let t = Thread.create (fun () -> Thread.delay 0.05; flag := true) () in
  Thread.join t;
  Printf.printf "delay: %b\n" !flag;
  let t = Thread.create (fun () -> raise Exit) () in
  Thread.join t;
  let t = Thread.create (fun () -> if true then raise Thread.Exit; print_endline "not reached") () in
  Thread.join t;
  print_endline "done"
