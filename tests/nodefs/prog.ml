(* --node-fs: the real file system, and the current directory, which the
   worker thread running compiled code keeps itself (node's workers cannot
   change the process's) *)
let () =
  let here = Sys.getcwd () in
  Sys.chdir "sub";
  Printf.printf "in sub: %b %s\n" (Sys.file_exists "data.txt") (Filename.basename (Sys.getcwd ()));
  let ic = open_in "data.txt" in
  print_endline (input_line ic);
  close_in ic;
  Sys.chdir "..";
  Printf.printf "back: %b %b\n" (Sys.getcwd () = here) (Sys.file_exists "prog.ml");
  (try Sys.chdir "missing" with Sys_error e -> print_endline e);
  (try Sys.chdir "prog.ml" with Sys_error e -> print_endline e);
  Sys.chdir "/";
  Printf.printf "root: %s %b\n" (Sys.getcwd ()) (Sys.is_directory "tmp")
