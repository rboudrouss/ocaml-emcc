(* pcre2 bindings + the libpcre2-8 recipe (conf-libpcre2-8) *)
let () =
  let text = "2024-01-15 alice@example.com, 2025-12-31 bob@test.org; 1999-07-04 carol@old.net" in
  let rex = Pcre2.regexp {|(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2}) (?<user>\w+)@(?<host>[\w.]+)|} in
  Array.iter
    (fun ss ->
      Printf.printf "%s/%s/%s %s at %s\n" (Pcre2.get_named_substring rex "day" ss)
        (Pcre2.get_named_substring rex "month" ss) (Pcre2.get_named_substring rex "year" ss)
        (Pcre2.get_named_substring rex "user" ss) (Pcre2.get_named_substring rex "host" ss))
    (Pcre2.exec_all ~rex text);
  print_endline (Pcre2.replace ~pat:{|(\w+)@|} ~templ:"<$1>@" text);
  print_endline (String.concat "|" (Pcre2.split ~pat:"[,;] *" text));
  Printf.printf "%b %b\n" (Pcre2.pmatch ~pat:"^\\d+$" "12345") (Pcre2.pmatch ~pat:"^\\d+$" "12a45");
  (* UTF-8 and caseless *)
  let rex = Pcre2.regexp ~flags:[ `UTF; `CASELESS ] "é+t" in
  print_endline (Pcre2.replace ~rex ~templ:"[$&]" "ÉtÉ, éét, ETE");
  print_endline (String.concat "," (Array.to_list (Pcre2.extract_all_opt ~pat:"(a)|(b)" "ab" |> Array.map (fun a -> String.concat "/" (Array.to_list (Array.map (function Some s -> s | None -> "-") a))))))
