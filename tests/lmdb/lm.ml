(* lmdb: the LMDB C library (vendored), a memory-mapped database file *)
let () =
  let dir = "lmdb_test_db" in
  (try Array.iter (fun f -> Sys.remove (Filename.concat dir f)) (Sys.readdir dir); Sys.rmdir dir with Sys_error _ -> ());
  Sys.mkdir dir 0o755;
  let env = Lmdb.Env.(create Rw ~map_size:(16 * 1024 * 1024) ~max_maps:4) dir in
  let map = Lmdb.Map.(create Nodup ~key:Lmdb.Conv.string ~value:Lmdb.Conv.string ~name:"m") env in
  for i = 1 to 100 do Lmdb.Map.add map (Printf.sprintf "key%03d" i) (string_of_int (i * i)) done;
  Printf.printf "get key042: %s\n" (Lmdb.Map.get map "key042");
  Lmdb.Map.set map "key042" "changed";
  Printf.printf "after set: %s\n" (Lmdb.Map.get map "key042");
  (match Lmdb.Map.get map "missing" with _ -> print_endline "found?!" | exception Not_found -> print_endline "missing: Not_found");
  let sum = ref 0 in
  Lmdb.Cursor.iter ~f:(fun _k v -> sum := !sum + (try int_of_string v with _ -> 0)) map;
  Printf.printf "sum: %d, entries %d\n" !sum (Lmdb.Map.stat map).Lmdb.Mdb.entries;
  Lmdb.Map.remove map "key001";
  (match Lmdb.Txn.go Lmdb.Rw env (fun txn -> Lmdb.Map.add ~txn map "inside" "txn"; Lmdb.Txn.abort txn) with
   | None -> print_endline "aborted" | Some _ -> print_endline "committed?");
  Printf.printf "inside after abort: %b\n" (try ignore (Lmdb.Map.get map "inside"); true with Not_found -> false);
  Lmdb.Env.close env;
  Array.iter (fun f -> Sys.remove (Filename.concat dir f)) (Sys.readdir dir); Sys.rmdir dir;
  print_endline "done"
