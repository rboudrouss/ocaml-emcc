(* The local time zone's file, as core's Timezone.local reads it ($TZ, else
   /etc/localtime): it gives the offset Unix.localtime uses *)
let read file = In_channel.with_open_bin file In_channel.input_all

let be32 s i = Int32.to_int (String.get_int32_be s i)

(* the offset of a version 1 tzfile at time t (times as int32: 31-bit
   ints on wasm32) *)
let offset s t =
  let timecnt = be32 s 32 in
  let idx = ref 0 in
  for k = 0 to timecnt - 1 do
    if Int32.compare (String.get_int32_be s (44 + (4 * k))) t <= 0 then idx := Char.code s.[44 + (4 * timecnt) + k]
  done;
  be32 s (44 + (5 * timecnt) + (6 * !idx))

let () =
  let file =
    match Sys.getenv_opt "TZ" with
    | Some z when z <> "" -> Filename.concat (Option.value (Sys.getenv_opt "TZDIR") ~default:"/usr/share/zoneinfo") z
    | _ -> "/etc/localtime"
  in
  let s = read file in
  Printf.printf "tzfile: %b\n" (String.sub s 0 4 = "TZif");
  (* at a few times, the tzfile's offset and that of Unix.localtime *)
  List.iter
    (fun t ->
      let lt = Unix.localtime t and gt = Unix.gmtime t in
      (* (the day may differ by one, across a year too) *)
      let days = compare (lt.Unix.tm_year, lt.tm_yday) (gt.Unix.tm_year, gt.tm_yday) in
      let d =
        (days * 86400) + ((lt.tm_hour - gt.tm_hour) * 3600) + ((lt.tm_min - gt.tm_min) * 60) + (lt.tm_sec - gt.tm_sec)
      in
      Printf.printf "%.0f: localtime %d, tzfile %d\n" t d (offset s (Int32.of_float t)))
    [ 0.; 1e9; 1.7e9; 1.72e9; 2e9 ]
