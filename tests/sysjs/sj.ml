(* Sys_js: channels redirected to functions, files, mounted paths *)
open Js_of_ocaml

let main () =
  let buf = Buffer.create 16 in
  Sys_js.set_channel_flusher stderr (fun s -> Buffer.add_string buf ("[" ^ s ^ "]"));
  prerr_string "hello";
  flush stderr;
  prerr_endline " world";
  Printf.eprintf "%d%c%!" 42 '\xe9';
  print_endline (String.escaped (Buffer.contents buf));
  let chunks = ref [ "line 1\nline 2\n"; "partial"; " line\n"; "no newline" ] in
  Sys_js.set_channel_filler stdin (fun () -> match !chunks with [] -> "" | c :: l -> chunks := l; c);
  (try
     while true do
       Printf.printf "read %S\n" (input_line stdin)
     done
   with End_of_file -> print_endline "end of input");
  Sys_js.create_file ~name:"/static/created.txt" ~content:"created";
  Printf.printf "read_file: %s\n" (Sys_js.read_file ~name:"/static/created.txt");
  Sys_js.mount ~path:"/virtual" (fun ~prefix ~path ->
      Printf.printf "asked for %s in %s\n" path prefix;
      if path = "dir/a.txt" then Some "the content of a" else None);
  Printf.printf "mounted: %b\n" (List.mem "/virtual/" (Sys_js.mount_point ()));
  let ic = open_in "/virtual/dir/a.txt" in
  Printf.printf "a.txt: %s\n" (input_line ic);
  close_in ic;
  Printf.printf "a.txt again (no ask): %b\n" (Sys.file_exists "/virtual/dir/a.txt");
  Printf.printf "missing: %b\n" (Sys.file_exists "/virtual/missing");
  Sys_js.unmount ~path:"/virtual";
  Printf.printf "after unmount: %b, mounted: %b\n" (Sys.file_exists "/virtual/other") (List.mem "/virtual/" (Sys_js.mount_point ()))

let () = try main () with e -> Printf.printf "exception %s\n" (Printexc.to_string e)
