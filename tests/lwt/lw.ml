(* lwt + lwt.unix: scheduler, timers, files, pipes, processes-free I/O *)
open Lwt.Syntax

let main () =
  let* () = Lwt_unix.sleep 0.05 in
  print_endline "slept";
  let order = ref [] in
  let t1 = let* () = Lwt_unix.sleep 0.03 in order := "b" :: !order; Lwt.return () in
  let t2 = let* () = Lwt_unix.sleep 0.01 in order := "a" :: !order; Lwt.return () in
  let* () = Lwt.join [ t1; t2 ] in
  Printf.printf "order: %s\n" (String.concat "," (List.rev !order));
  let file = "lwt_test.txt" in
  let* () = Lwt_io.with_file ~mode:Lwt_io.Output file (fun oc ->
    Lwt_list.iter_s (fun i -> Lwt_io.fprintf oc "line %d\n" i) [ 1; 2; 3 ]) in
  let* lines = Lwt_io.with_file ~mode:Lwt_io.Input file (fun ic -> Lwt_stream.to_list (Lwt_io.read_lines ic)) in
  Printf.printf "read back: %s\n" (String.concat "|" lines);
  let* st = Lwt_unix.stat file in
  Printf.printf "size: %d\n" st.Unix.st_size;
  let* fd = Lwt_unix.openfile file [ Unix.O_RDONLY ] 0 in
  let buf = Bytes.create 4 in
  let* n = Lwt_unix.read fd buf 0 4 in
  Printf.printf "read %d: %s\n" n (Bytes.sub_string buf 0 n);
  let* _ = Lwt_unix.lseek fd 2 Unix.SEEK_SET in
  let* n = Lwt_unix.read fd buf 0 4 in
  Printf.printf "after seek %d: %s\n" n (Bytes.sub_string buf 0 n);
  let* () = Lwt_unix.close fd in
  let* () = Lwt_unix.unlink file in
  let* exists = Lwt_unix.file_exists file in
  Printf.printf "exists after unlink: %b\n" exists;
  (* a pipe between two threads *)
  let ic, oc = Lwt_io.pipe () in
  let writer = let* () = Lwt_io.write_line oc "through the pipe" in Lwt_io.close oc in
  let* l = Lwt_io.read_line ic in
  let* () = writer in
  print_endline l;
  (* timeouts and cancellation *)
  let* r = Lwt.pick [ (let* () = Lwt_unix.sleep 1.0 in Lwt.return "slow"); (let* () = Lwt_unix.sleep 0.01 in Lwt.return "fast") ] in
  print_endline r;
  let* r = Lwt.catch (fun () -> Lwt_unix.with_timeout 0.01 (fun () -> let* () = Lwt_unix.sleep 1. in Lwt.return "no")) (function Lwt_unix.Timeout -> Lwt.return "timeout" | e -> raise e) in
  print_endline r;
  let s = Lwt_stream.of_list [ 1; 2; 3; 4 ] in
  let* sum = Lwt_stream.fold ( + ) (Lwt_stream.map (fun x -> x * x) s) 0 in
  Printf.printf "sum of squares: %d\n" sum;
  let* () = Lwt_unix.mkdir "lwt_dir" 0o755 in
  let* () = Lwt_unix.rmdir "lwt_dir" in
  let* t = Lwt_unix.getcwd () in
  Printf.printf "cwd absolute: %b\n" (t <> "" && t.[0] = '/');
  Lwt.return ()

let () = Lwt_main.run (main ()); print_endline "done"
