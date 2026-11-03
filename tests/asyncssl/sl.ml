(* async_ssl: a TLS server and its client, connected by pipes, with a
   self-signed certificate (pems.ml, written to files first) *)
open! Core
open! Async

let read r = match%map Pipe.read r with `Ok s -> s | `Eof -> "(end)"

let main () =
  Out_channel.write_all "sl-cert.pem" ~data:Pems.cert;
  Out_channel.write_all "sl-key.pem" ~data:Pems.key;
  let net_c2s_r, net_c2s_w = Pipe.create () and net_s2c_r, net_s2c_w = Pipe.create () in
  let capp_r, capp_w = Pipe.create () and cout_r, cout_w = Pipe.create () in
  let sapp_r, sapp_w = Pipe.create () and sout_r, sout_w = Pipe.create () in
  let server =
    Async_ssl.Ssl.server ~crt_file:"sl-cert.pem" ~key_file:"sl-key.pem" ~app_to_ssl:sapp_r ~ssl_to_app:sout_w
      ~net_to_ssl:net_c2s_r ~ssl_to_net:net_s2c_w ()
  in
  let client = Async_ssl.Ssl.client ~ca_file:"sl-cert.pem" ~app_to_ssl:capp_r ~ssl_to_app:cout_w ~net_to_ssl:net_s2c_r ~ssl_to_net:net_c2s_w () in
  let%bind client = client and server = server in
  let client = Or_error.ok_exn client and _server = Or_error.ok_exn server in
  printf "handshake done, version %s\n"
    (Sexp.to_string [%sexp (Async_ssl.Ssl.Connection.version client : Async_ssl.Version.t)]);
  Pipe.write_without_pushback capp_w "hello over tls";
  let%bind m = read sout_r in
  printf "server got %S\n" m;
  Pipe.write_without_pushback sapp_w (String.uppercase m);
  let%bind r = read cout_r in
  printf "client got %S\n" r;
  printf "peer certificate: %b\n" (Option.is_some (Async_ssl.Ssl.Connection.peer_certificate client));
  Core_unix.unlink "sl-cert.pem";
  Core_unix.unlink "sl-key.pem";
  Writer.flushed (force Writer.stdout)

let () =
  don't_wait_for (let%map () = main () in shutdown 0);
  never_returns (Scheduler.go ())
