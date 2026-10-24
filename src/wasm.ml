(* The imports of a wasm module (module name, field name), read from its
   import section: what a standalone OUT.wasm needs from its host. *)

let imports path =
  let s = Compat.read_file path in
  let len = String.length s in
  let pos = ref 8 in
  let byte () =
    if !pos >= len then failwith "truncated";
    let c = Char.code s.[!pos] in
    incr pos;
    c
  in
  let rec leb shift acc =
    let b = byte () in
    let acc = acc lor ((b land 0x7f) lsl shift) in
    if b land 0x80 <> 0 then leb (shift + 7) acc else acc
  in
  let uleb () = leb 0 0 in
  let name () =
    let n = uleb () in
    let r = String.sub s !pos n in
    pos := !pos + n;
    r
  in
  let limits () =
    let flags = byte () in
    ignore (uleb ());
    if flags land 1 <> 0 then ignore (uleb ())
  in
  let reftype () = match byte () with 0x63 | 0x64 -> ignore (uleb ()) | _ -> () in
  let rec sections acc =
    if !pos >= len then acc
    else
      let id = byte () in
      let size = uleb () in
      let next = !pos + size in
      let acc =
        if id <> 2 then acc
        else
          List.init (uleb ()) (fun _ ->
              let m = name () in
              let f = name () in
              (match byte () with
              | 0 -> ignore (uleb ()) (* function: type index *)
              | 1 -> reftype (); limits () (* table *)
              | 2 -> limits () (* memory *)
              | 3 -> reftype (); ignore (byte ()) (* global: type, mutability *)
              | _ -> ignore (byte ()); ignore (uleb ()) (* tag: attribute, type index *));
              (m, f))
      in
      pos := next;
      sections acc
  in
  if len < 8 || String.sub s 0 4 <> "\000asm" then failwith (path ^ ": not a wasm module");
  try sections [] with Failure _ | Invalid_argument _ -> failwith (path ^ ": malformed wasm module")
