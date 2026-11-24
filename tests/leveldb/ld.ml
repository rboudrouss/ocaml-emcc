(* leveldb: LevelDB (C++, with Snappy), a small write buffer: its memtables
   are written to tables and compacted, in its background thread *)
let () =
  let dir = "leveldb_test_db" in
  ignore (LevelDB.destroy dir);
  let db = LevelDB.open_db ~write_buffer_size:(64 * 1024) dir in
  for i = 0 to 19_999 do
    LevelDB.put db (Printf.sprintf "key%05d" i) (String.make 50 (Char.chr (65 + (i mod 26))) ^ string_of_int i)
  done;
  LevelDB.delete db "key00042";
  Printf.printf "key12345: %s\n" (Option.value (LevelDB.get db "key12345") ~default:"?");
  Printf.printf "key00042: %b\n" (LevelDB.mem db "key00042");
  let n = ref 0 and last = ref "" in
  LevelDB.iter_from (fun k _ -> incr n; last := k; !n < 10) db "key19990";
  Printf.printf "from key19990: %d keys, the last %s\n" !n !last;
  LevelDB.compact_range db ~from_key:None ~to_key:None;
  Printf.printf "files at level 0 after compaction: %s\n"
    (Option.value (LevelDB.get_property db "leveldb.num-files-at-level0") ~default:"?");
  LevelDB.close db;
  (* reopened *)
  let db = LevelDB.open_db dir in
  Printf.printf "reopened, key19999: %s\n" (Option.value (LevelDB.get db "key19999") ~default:"?");
  LevelDB.close db;
  print_endline (string_of_bool (LevelDB.destroy dir))
