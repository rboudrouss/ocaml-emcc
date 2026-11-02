(* Lwt over sockets: a TCP server and its clients, names, timeouts *)
open Lwt.Syntax

let handle fd =
  let ic = Lwt_io.of_fd ~mode:Lwt_io.Input fd and oc = Lwt_io.of_fd ~mode:Lwt_io.Output fd in
  let* l = Lwt_io.read_line ic in
  let* () = Lwt_io.write_line oc (String.uppercase_ascii l) in
  let* () = Lwt_io.flush oc in
  Lwt_unix.close fd

let main () =
  let* ais = Lwt_unix.getaddrinfo "localhost" "0" [ Unix.AI_FAMILY Unix.PF_INET; Unix.AI_SOCKTYPE Unix.SOCK_STREAM ] in
  let srv = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Lwt_unix.setsockopt srv Unix.SO_REUSEADDR true;
  let* () = Lwt_unix.bind srv (List.hd ais).Unix.ai_addr in
  Lwt_unix.listen srv 10;
  let addr = Lwt_unix.getsockname srv in
  let rec serve n =
    if n = 0 then Lwt.return ()
    else
      let* fd, _ = Lwt_unix.accept srv in
      Lwt.async (fun () -> handle fd);
      serve (n - 1)
  in
  let server = serve 3 in
  let* replies =
    Lwt_list.map_p
      (fun i ->
        Lwt_io.with_connection addr (fun (ic, oc) ->
            let* () = Lwt_io.write_line oc (Printf.sprintf "client %d" i) in
            Lwt_io.read_line ic))
      [ 1; 2; 3 ]
  in
  List.iter print_endline replies;
  let* () = server in
  (* nobody writes: the read times out *)
  let a, b = Lwt_unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let* r =
    Lwt.catch
      (fun () -> Lwt_unix.with_timeout 0.05 (fun () -> let* n = Lwt_unix.read a (Bytes.create 1) 0 1 in Lwt.return (string_of_int n)))
      (function Lwt_unix.Timeout -> Lwt.return "timeout" | e -> Lwt.fail e)
  in
  print_endline r;
  let* _ = Lwt_unix.write_string b "z" 0 1 in
  let buf = Bytes.create 1 in
  let* n = Lwt_unix.read a buf 0 1 in
  Printf.printf "socketpair: %d %s\n" n (Bytes.to_string buf);
  let* () = Lwt_unix.close a and* () = Lwt_unix.close b and* () = Lwt_unix.close srv in
  (* refused *)
  let* r =
    Lwt.catch
      (fun () -> let* _ = Lwt_io.open_connection (Unix.ADDR_INET (Unix.inet_addr_loopback, 1)) in Lwt.return "connected?")
      (function Unix.Unix_error (Unix.ECONNREFUSED, _, _) -> Lwt.return "refused" | e -> Lwt.fail e)
  in
  print_endline r;
  Lwt.return ()

let () = Lwt_main.run (main ())
