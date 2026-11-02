(* Sockets: a TCP server and its client in one program, UDP, names *)
open Unix

let port_of = function ADDR_INET (_, p) -> p | ADDR_UNIX _ -> -1
let show = function ADDR_INET (a, _) -> string_of_inet_addr a | ADDR_UNIX p -> "unix:" ^ p
let loopback p = ADDR_INET (inet_addr_loopback, p)

let () =
  let srv = socket PF_INET SOCK_STREAM 0 in
  setsockopt srv SO_REUSEADDR true;
  (* (wasmer: the options of a socket before it listens) *)
  Printf.printf "type stream %b, reuseaddr %b\n" (getsockopt_int srv SO_TYPE = 1) (getsockopt srv SO_REUSEADDR);
  bind srv (loopback 0);
  listen srv 5;
  let addr = getsockname srv in
  Printf.printf "listening on %s, port given %b\n" (show addr) (port_of addr > 0);
  let cli = socket PF_INET SOCK_STREAM 0 in
  connect cli addr;
  setsockopt cli TCP_NODELAY true;
  Printf.printf "nodelay %b, no error %b\n" (getsockopt cli TCP_NODELAY) (getsockopt_error cli = None);
  let conn, peer = accept srv in
  Printf.printf "peer %s, the client %b, server side %b\n" (show peer) (getsockname cli = peer) (getpeername conn = peer);
  Printf.printf "stat: socket %b\n" ((fstat conn).st_kind = S_SOCK);
  ignore (write_substring cli "ping" 0 4);
  let b = Bytes.create 16 in
  let n = read conn b 0 16 in
  Printf.printf "server got %S\n" (Bytes.sub_string b 0 n);
  ignore (send_substring conn "pong" 0 4 []);
  shutdown conn SHUTDOWN_SEND;
  (match select [ cli ] [] [] 5.0 with [ _ ], _, _ -> print_endline "select: readable" | _ -> print_endline "select: timeout");
  let n = recv cli b 0 16 [] in
  Printf.printf "client got %S, then end of file %b\n" (Bytes.sub_string b 0 n) (recv cli b 0 16 [] = 0);
  close cli;
  close conn;
  (* channels *)
  let ic, oc = open_connection addr in
  let conn, _ = accept srv in
  let sic = in_channel_of_descr conn and soc = out_channel_of_descr conn in
  output_string oc "hello server\n";
  flush oc;
  output_string soc (String.uppercase_ascii (input_line sic) ^ "\n");
  flush soc;
  Printf.printf "channels: %s\n" (input_line ic);
  shutdown_connection ic;
  close_in ic;
  close conn;
  (* nothing to accept *)
  set_nonblock srv;
  (match accept srv with
   | _ -> print_endline "accepted?"
   | exception Unix_error ((EAGAIN | EWOULDBLOCK), _, _) -> print_endline "accept would block");
  close srv;
  (* UDP *)
  let u1 = socket PF_INET SOCK_DGRAM 0 and u2 = socket PF_INET SOCK_DGRAM 0 in
  bind u1 (loopback 0);
  bind u2 (loopback 0);
  ignore (sendto_substring u2 "datagram" 0 8 [] (getsockname u1));
  let n, from = recvfrom u1 b 0 16 [] in
  Printf.printf "udp got %S from the sender %b\n" (Bytes.sub_string b 0 n) (from = getsockname u2);
  close u1;
  close u2;
  (* names *)
  let ais = getaddrinfo "localhost" "80" [ AI_FAMILY PF_INET; AI_SOCKTYPE SOCK_STREAM ] in
  (* (/etc/hosts may name it twice) *)
  List.sort_uniq compare (List.map (fun ai -> ai.ai_addr) ais)
  |> List.iter (fun a -> Printf.printf "localhost: %s port %d\n" (show a) (port_of a));
  let ais = getaddrinfo "10.1.2.3" "" [ AI_SOCKTYPE SOCK_DGRAM ] in
  List.iter (fun ai -> Printf.printf "numeric: %s\n" (show ai.ai_addr)) ais;
  Printf.printf "unknown host: %d\n" (List.length (getaddrinfo "no-such-host.invalid" "" []));
  let h = gethostbyname "localhost" in
  Printf.printf "gethostbyname: 127.0.0.1 %b\n" (Array.mem inet_addr_loopback h.h_addr_list);
  (match gethostbyname "no-such-host.invalid" with
   | _ -> print_endline "found?"
   | exception Not_found -> print_endline "gethostbyname: Not_found");
  Printf.printf "tcp is %d\n" (getprotobyname "tcp").p_proto;
  let ni = getnameinfo (ADDR_INET (inet_addr_of_string "10.1.2.3", 8080)) [ NI_NUMERICHOST; NI_NUMERICSERV ] in
  Printf.printf "getnameinfo: %s %s\n" ni.ni_hostname ni.ni_service
