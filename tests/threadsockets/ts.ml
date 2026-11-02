(* threads and sockets: a server thread accepting, a thread per connection, client threads *)
let () =
  let srv = Unix.socket PF_INET SOCK_STREAM 0 in
  Unix.bind srv (ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen srv 5;
  let addr = Unix.getsockname srv in
  let served = ref [] and m = Mutex.create () in
  let server = Thread.create (fun () ->
    let ts = List.init 4 (fun _ ->
      let c, _ = Unix.accept srv in
      Thread.create (fun c ->
        let ic = Unix.in_channel_of_descr c and oc = Unix.out_channel_of_descr c in
        let l = input_line ic in
        Mutex.lock m; served := l :: !served; Mutex.unlock m;
        output_string oc (String.uppercase_ascii l ^ "\n"); flush oc; Unix.close c) c) in
    List.iter Thread.join ts) () in
  let clients = List.init 4 (fun i -> Thread.create (fun i ->
    Thread.delay 0.05;
    let ic, oc = Unix.open_connection addr in
    output_string oc (Printf.sprintf "client %d\n" i); flush oc;
    let r = input_line ic in Unix.shutdown_connection ic; close_in ic; r) i) in
  List.iter Thread.join clients;
  Thread.join server;
  List.iter print_endline (List.sort compare !served)
