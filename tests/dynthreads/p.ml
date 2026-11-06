(* Threads started by the plugin while it is loaded, and functions run
   later by the program's threads *)
let scale = 10_000

let () =
  let ts = List.init 3 (fun i -> Thread.create (fun () -> App.add (10 * (i + 1))) ()) in
  List.iter Thread.join ts;
  Printf.printf "plugin threads: %d\n%!" !App.total;
  App.register (fun n -> 100 * n);
  App.register (fun n -> 1000 * n)
