(* core on the target: Int63 (an int64 on wasm32), times, maps, bin_prot, sexps, dates, the local time zone *)
open Core

let () =
  let a = Int63.of_int64_exn 4_611_686_018_427_387_903L in
  printf "max int63 %s\n" (Int63.to_string a);
  printf "div %s\n" (Int63.to_string Int63.(a / of_int 7));
  printf "mul %s\n" (Int63.to_string Int63.(of_int 1_000_000 * of_int 1_000_000));
  printf "span %s\n" (Time_ns.Span.to_string (Time_ns.Span.of_sec 1.5));
  let t = Time_ns.of_int63_ns_since_epoch (Int63.of_int64_exn 1_700_000_000_123_456_789L) in
  printf "time %s\n" (Time_ns.to_string_utc t);
  printf "time_float %s\n" (Time_float.to_string_utc (Time_float.of_span_since_epoch (Time_float.Span.of_sec 1e9)));
  printf "now > 2020: %b\n" Time_ns.(now () > of_int63_ns_since_epoch (Int63.of_int64_exn 1_577_836_800_000_000_000L));
  let m = Map.of_alist_exn (module String) [ ("a", 1); ("b", 2) ] in
  print_s [%sexp (m : int Map.M(String).t)];
  let h = Hashtbl.create (module Int) in
  Hashtbl.set h ~key:42 ~data:"x";
  printf "hashtbl %d\n" (Hashtbl.length h);
  let buf = Bin_prot.Utils.bin_dump Int63.bin_writer_t a in
  printf "bin_prot %d bytes, back %s\n" (Bigstring.length buf)
    (Int63.to_string (Int63.bin_read_t buf ~pos_ref:(ref 0)));
  printf "sexp %s\n" (Sexp.to_string [%sexp (Int63.max_value : Int63.t), (Float.pi : float)]);
  printf "date %s\n" (Date.to_string (Date.add_days (Date.of_string "2024-02-28") 2))

let () =
  let zone = force Time_float_unix.Zone.local in
  let t = Time_float.of_span_since_epoch (Time_float.Span.of_sec 1.72e9) in
  printf "local %s\n" (Time_float.to_string_abs t ~zone)
