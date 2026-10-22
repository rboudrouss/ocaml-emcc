(* sqlite3 bindings + the sqlite3 recipe (conf-sqlite3) *)
let check db = function
  | Sqlite3.Rc.OK | Sqlite3.Rc.DONE | Sqlite3.Rc.ROW -> ()
  | rc -> failwith (Sqlite3.Rc.to_string rc ^ ": " ^ Sqlite3.errmsg db)

let query db sql =
  Printf.printf "> %s\n" sql;
  check db
    (Sqlite3.exec_no_headers db sql ~cb:(fun row ->
         print_endline
           (String.concat " | " (Array.to_list (Array.map (function Some s -> s | None -> "NULL") row)))))

let () =
  let file = Filename.concat (Filename.get_temp_dir_name ()) "ocaml-emcc-sqlite-test.db" in
  if Sys.file_exists file then Sys.remove file;
  let db = Sqlite3.db_open file in
  check db (Sqlite3.exec db "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL, data BLOB)");
  let st = Sqlite3.prepare db "INSERT INTO t (name, score, data) VALUES (?, ?, ?)" in
  List.iteri
    (fun i n ->
      check db (Sqlite3.reset st);
      check db (Sqlite3.bind_text st 1 n);
      check db (Sqlite3.bind_double st 2 (float_of_int (i * i) *. 1.25));
      check db (Sqlite3.bind_blob st 3 (String.make i '\000'));
      check db (Sqlite3.step st))
    [ "alice"; "bob"; "carol"; "dave"; "eve" ];
  check db (Sqlite3.finalize st);
  query db "SELECT id, name, score, length(data) FROM t ORDER BY score DESC";
  query db "SELECT count(*), sum(score), avg(score), group_concat(name, ',') FROM t";
  query db "SELECT printf('%.3f', sqrt(2.0)), round(pi(), 5), 1 << 40, 9223372036854775807";
  query db "SELECT json_object('n', name, 's', score) FROM t WHERE id <= 2";
  query db "WITH RECURSIVE f(n, x) AS (SELECT 1, 1 UNION ALL SELECT n + 1, x * (n + 1) FROM f WHERE n < 20) SELECT max(x) FROM f";
  (* a prepared statement read back with typed columns *)
  let st = Sqlite3.prepare db "SELECT name, score FROM t WHERE score > ?" in
  check db (Sqlite3.bind_double st 1 2.0);
  while Sqlite3.step st = Sqlite3.Rc.ROW do
    Printf.printf "%s %g\n" (Sqlite3.column_text st 0) (Sqlite3.column_double st 1)
  done;
  check db (Sqlite3.finalize st);
  ignore (Sqlite3.db_close db);
  (* the file persists *)
  let db = Sqlite3.db_open ~mode:`READONLY file in
  query db "SELECT count(*) FROM t";
  ignore (Sqlite3.db_close db);
  Sys.remove file
