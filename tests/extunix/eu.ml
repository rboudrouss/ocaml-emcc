(* extunix: many small POSIX bindings, some optional (feature tests) *)
open ExtUnix.Specific
let () =
  let fd = Unix.openfile "eu.txt" [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
  ignore (Unix.write_substring fd "0123456789" 0 10);
  Printf.printf "pread: %s\n" (let b = Bytes.create 4 in let n = pread fd 3 b 0 4 in Bytes.sub_string b 0 n);
  ignore (pwrite fd 0 "ab" 0 2);
  fsync fd;
  Unix.ftruncate fd 6;
  Printf.printf "size: %d\n" (Unix.fstat fd).Unix.st_size;
  Unix.close fd;
  Printf.printf "content: %s\n" (let ic = open_in_bin "eu.txt" in let s = really_input_string ic (in_channel_length ic) in close_in ic; s);
  Unix.unlink "eu.txt";
  Printf.printf "endian: %d %ld %Lx\n" (BigEndian.get_uint16 "\x01\x02" 0) (LittleEndian.get_int32 "\x01\x02\x03\x04" 0)
    (BigEndian.get_int64 "\x01\x02\x03\x04\x05\x06\x07\x08" 0);
  Printf.printf "is_open_descr stdin: %b\n" (is_open_descr Unix.stdin);
  Printf.printf "realpath: %b\n" (realpath "." <> "");
  Printf.printf "uname sysname: %b\n" ((uname ()).Uname.sysname <> "");
  Printf.printf "have eventfd: %b, have splice: %b\n" (Option.is_some (ExtUnix.All.have "eventfd")) (Option.is_some (ExtUnix.All.have "splice"));
  print_endline "done"
