(* posix-time2, posix-socket, posix-stat: ctypes bindings whose C types and
   structs (timespec, tm, sockaddr_in, struct stat...) are laid out by C
   programs at build time, so must be those of the target *)
open Ctypes
module T = Posix_time2
module S = Posix_socket

let () =
  (* the sizes of C types follow the target's word size *)
  Printf.printf "size_t = pointer: %b, off_t 64 bits: %b, long = word: %b\n"
    (sizeof Posix_types.size_t = sizeof (ptr void))
    (sizeof Posix_types.off_t = 8)
    (sizeof long * 8 = Sys.word_size);
  (* struct timespec / struct tm *)
  let a = T.Timespec.create 1L 999_999_999L and b = T.Timespec.create 2L 3L in
  Printf.printf "timespec %s %s %d\n" (T.Timespec.to_string (T.Timespec.add a b))
    (T.Timespec.to_string (T.Timespec.sub b a)) (T.Timespec.compare a b);
  let tm = T.gmtime 1_700_000_000L in
  Printf.printf "gmtime %04d-%02d-%02d %02d:%02d:%02d wday %d yday %d\n" (tm.tm_year + 1900)
    (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec tm.tm_wday tm.tm_yday;
  let t0 = T.clock_gettime `Monotonic in
  T.nanosleep (T.Timespec.create 0L 20_000_000L);
  let t1 = T.clock_gettime `Monotonic in
  Printf.printf "monotonic: slept >= 20ms %b\n"
    (T.Timespec.compare (T.Timespec.sub t1 t0) (T.Timespec.create 0L 20_000_000L) >= 0);
  let tv = T.gettimeofday () in
  Printf.printf "gettimeofday near Unix.gettimeofday: %b\n"
    (Float.abs (Int64.to_float tv.tv_sec -. Unix.gettimeofday ()) < 5.);
  (* sockaddr_in, sockaddr_in6, byte order, numeric getaddrinfo *)
  Printf.printf "htons 0x1234 = 0x%x, htonl 1 = 0x%lx\n"
    (Unsigned.UInt16.to_int (S.htons (Unsigned.UInt16.of_int 0x1234)))
    (Unsigned.UInt32.to_int32 (S.htonl Unsigned.UInt32.one));
  let sa = S.from_unix_sockaddr (Unix.ADDR_INET (Unix.inet_addr_of_string "10.1.2.3", 443)) in
  let sin = !@ (from_voidp S.sockaddr_in_t (to_voidp sa)) in
  Printf.printf "sockaddr_in len %d = %d, port %d\n" (S.sockaddr_len sa) (sizeof S.sockaddr_in_t)
    (Unsigned.UInt16.to_int (S.ntohs (getf sin S.SockaddrInet.sin_port)));
  let show sa = match S.to_unix_sockaddr sa with
    | Unix.ADDR_INET (a, p) -> Printf.sprintf "%s:%d" (Unix.string_of_inet_addr a) p
    | Unix.ADDR_UNIX s -> s in
  List.iter (fun host ->
      let l = S.getaddrinfo ~port:(`Int 8080) host in
      Printf.printf "getaddrinfo %s: %s\n" host (String.concat " " (List.sort_uniq compare (List.map show l))))
    [ "127.0.0.1"; "::1"; "192.168.10.20" ];
  (* struct stat *)
  let f = "px.tmp" in
  let oc = open_out_bin f in
  output_string oc (String.make 1234 'x'); close_out oc;
  Posix_stat.chmod f (Posix_types.Mode.of_int 0o640);
  let st = Posix_stat.stat f in
  Printf.printf "stat: size %s, regular %b, dir %b, perm %o, nlink %s\n"
    (Posix_types.Off.to_string st.st_size) (Posix_stat.s_isreg st.st_mode)
    (Posix_stat.s_isdir st.st_mode) (Posix_types.Mode.to_int st.st_mode land 0o777)
    (Posix_types.Nlink.to_string st.st_nlink);
  let fd = Unix.openfile f [ Unix.O_RDONLY ] 0 in
  let fst = Posix_stat.fstat fd in
  Unix.close fd;
  Printf.printf "fstat: same size %b, same inode %b, mtime near now %b\n" (fst.st_size = st.st_size)
    (fst.st_ino = st.st_ino)
    (Float.abs (Int64.to_float fst.st_mtim.tv_sec -. Unix.time ()) < 60.);
  Sys.remove f;
  Posix_stat.mkdir "px.d" (Posix_types.Mode.of_int 0o755);
  Printf.printf "mkdir: dir %b\n" (Posix_stat.s_isdir (Posix_stat.stat "px.d").st_mode);
  Unix.rmdir "px.d";
  match Posix_stat.stat "px.missing" with
  | _ -> print_endline "stat of a missing file succeeded"
  | exception Unix.Unix_error (e, _, _) -> Printf.printf "missing: %s\n" (Unix.error_message e)
