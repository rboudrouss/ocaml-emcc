(* --owi: the atomic instructions (threads proposal) of a module that runs
   on one thread, replaced by plain ones for a host without them (owi).

   The C of the sysroot is compiled with -pthread (Toolchain.compile_flags),
   so the runtime and the stubs have atomic instructions even in a program
   linked without --threads, whose memory is not shared.  On one thread the
   replacement is exact, but for the alignment checks of the atomic
   instructions:
   - an atomic load or store is the plain one;
   - a read-modify-write or a compare-exchange is a call to a function added
     to the module: a load, the operation, a store, the old value;
   - atomic.fence is nothing;
   - memory.atomic.notify returns 0 (nobody waits);
   - memory.atomic.wait traps, as on a memory that is not shared. *)

exception Unsupported of string

let unsupported fmt = Printf.ksprintf (fun s -> raise (Unsupported s)) fmt

type reader = { s : string; mutable pos : int }

let byte r =
  if r.pos >= String.length r.s then unsupported "truncated";
  let c = Char.code r.s.[r.pos] in
  r.pos <- r.pos + 1;
  c

let rec skip_leb r = if byte r land 0x80 <> 0 then skip_leb r

let uleb r =
  let rec go shift acc =
    let b = byte r in
    let acc = acc lor ((b land 0x7f) lsl shift) in
    if b land 0x80 <> 0 then go (shift + 7) acc else acc
  in
  go 0 0

let add_uleb b n =
  let rec go n =
    let low = n land 0x7f and n = n lsr 7 in
    if n = 0 then Buffer.add_char b (Char.chr low)
    else (
      Buffer.add_char b (Char.chr (low lor 0x80));
      go n)
  in
  go n

let add_sleb b n =
  let rec go n =
    let low = n land 0x7f and rest = n asr 7 in
    if (rest = 0 && low land 0x40 = 0) || (rest = -1 && low land 0x40 <> 0) then Buffer.add_char b (Char.chr low)
    else (
      Buffer.add_char b (Char.chr (low lor 0x80));
      go rest)
  in
  go n

let heaptype = skip_leb

let valtype r = match byte r with 0x63 | 0x64 -> heaptype r | _ -> ()

(* 0x40, a value type, or a type index (s33) *)
let blocktype r =
  let b = byte r in
  if b = 0x63 || b = 0x64 then heaptype r else if b land 0x80 <> 0 then skip_leb r

(* the bytes of a memarg: alignment (bit 6: a memory index follows), offset *)
let memarg r =
  let start = r.pos in
  if uleb r land 0x40 <> 0 then skip_leb r;
  skip_leb r;
  String.sub r.s start (r.pos - start)

let limits r =
  let flags = byte r in
  if flags land 2 <> 0 then unsupported "the memory is shared (a program with threads)";
  skip_leb r;
  if flags land 1 <> 0 then skip_leb r

let i32 = 0x7f and i64 = 0x7e

(* the plain instruction of each atomic load and store, 0xFE 0x10 to 0x1D *)
let plain = [| 0x28; 0x29; 0x2D; 0x2F; 0x31; 0x33; 0x35; 0x36; 0x37; 0x3A; 0x3B; 0x3C; 0x3D; 0x3E |]

let load_op is64 width =
  match (is64, width) with
  | false, 32 -> 0x28
  | true, 64 -> 0x29
  | false, 8 -> 0x2D
  | false, 16 -> 0x2F
  | true, 8 -> 0x31
  | true, 16 -> 0x33
  | _ -> 0x35

let store_op is64 width =
  match (is64, width) with
  | false, 32 -> 0x36
  | true, 64 -> 0x37
  | false, 8 -> 0x3A
  | false, 16 -> 0x3B
  | true, 8 -> 0x3C
  | true, 16 -> 0x3D
  | _ -> 0x3E

(* The function standing for the atomic instruction 0xFE [n] with memarg
   [m]: its parameters, results, locals and code. *)
let helper n m =
  let code = Buffer.create 32 in
  let op c = Buffer.add_char code (Char.chr c) in
  let get i = op 0x20; add_uleb code i in
  let set i = op 0x21; add_uleb code i in
  let mem c = op c; Buffer.add_string code m in
  let finish params results locals = op 0x0B; (params, results, locals, Buffer.contents code) in
  match n with
  | 0x00 ->
      (* notify (address, count): the address checked, nobody woken up *)
      get 0; mem 0x28; op 0x1A; op 0x41; add_sleb code 0;
      finish [ i32; i32 ] [ i32 ] []
  | 0x01 | 0x02 ->
      (* wait (address, expected, timeout) *)
      op 0x00;
      finish [ i32; (if n = 0x02 then i64 else i32); i64 ] [ i32 ] []
  | _ ->
      (* groups of 7: add, sub, and, or, xor, xchg, cmpxchg; in each, the
         widths i32, i64, i32 8, i32 16, i64 8, i64 16, i64 32 *)
      let group = (n - 0x1E) / 7 in
      let is64, width =
        match (n - 0x1E) mod 7 with
        | 0 -> (false, 32)
        | 1 -> (true, 64)
        | 2 -> (false, 8)
        | 3 -> (false, 16)
        | 4 -> (true, 8)
        | 5 -> (true, 16)
        | _ -> (true, 32)
      in
      let t = if is64 then i64 else i32 in
      if group < 6 then (
        (* (address, value): the old value *)
        get 0; get 0; mem (load_op is64 width); set 2;
        if group = 5 then get 1
        else (
          get 2; get 1;
          op (if is64 then [| 0x7C; 0x7D; 0x83; 0x84; 0x85 |].(group) else [| 0x6A; 0x6B; 0x71; 0x72; 0x73 |].(group)));
        mem (store_op is64 width); get 2;
        finish [ i32; t ] [ t ] [ t ])
      else (
        (* (address, expected, replacement): the old value; expected wrapped
           to the width *)
        get 0; mem (load_op is64 width); set 3; get 3; get 1;
        if width < (if is64 then 64 else 32) then (
          op (if is64 then 0x42 else 0x41);
          add_sleb code ((1 lsl width) - 1);
          op (if is64 then 0x83 else 0x71));
        op (if is64 then 0x51 else 0x46);
        op 0x04; op 0x40; get 0; get 2; mem (store_op is64 width); op 0x0B;
        get 3;
        finish [ i32; t; t ] [ t ] [ t ])

(* Rewrites the body of a function (reader at its locals, up to [body_end])
   into [out]; [call n m] is the index of the function standing for 0xFE [n]
   with memarg [m].  Returns the number of atomic instructions replaced. *)
let lower_body r body_end out ~call =
  let copied = ref r.pos and count = ref 0 in
  let flush upto = Buffer.add_string out (String.sub r.s !copied (upto - !copied)) in
  for _ = 1 to uleb r do skip_leb r; valtype r done;
  while r.pos < body_end do
    let start = r.pos in
    match byte r with
    | 0x00 | 0x01 | 0x05 | 0x0A | 0x0B | 0x0F | 0x19 | 0x1A | 0x1B | 0xD1 | 0xD3 | 0xD4 -> ()
    | 0x02 | 0x03 | 0x04 | 0x06 -> blocktype r
    | 0x07 | 0x08 | 0x09 | 0x0C | 0x0D | 0x10 | 0x12 | 0x14 | 0x15 | 0x18 | 0xD2 | 0xD5 | 0xD6 -> skip_leb r
    | 0x20 | 0x21 | 0x22 | 0x23 | 0x24 | 0x25 | 0x26 -> skip_leb r
    | 0x0E -> for _ = 0 to uleb r do skip_leb r done
    | 0x11 | 0x13 -> skip_leb r; skip_leb r
    | 0x1C -> for _ = 1 to uleb r do valtype r done
    | 0x1F ->
        blocktype r;
        for _ = 1 to uleb r do
          match byte r with
          | 0 | 1 -> skip_leb r; skip_leb r
          | 2 | 3 -> skip_leb r
          | k -> unsupported "catch clause %d" k
        done
    | op when op >= 0x28 && op <= 0x3E -> ignore (memarg r)
    | 0x3F | 0x40 | 0x41 | 0x42 -> skip_leb r
    | 0x43 -> r.pos <- r.pos + 4
    | 0x44 -> r.pos <- r.pos + 8
    | op when op >= 0x45 && op <= 0xC4 -> ()
    | 0xD0 -> heaptype r
    | 0xFC -> (
        match uleb r with
        | n when n <= 7 -> ()
        | 8 | 10 | 12 | 14 -> skip_leb r; skip_leb r
        | 9 | 11 | 13 | 15 | 16 | 17 -> skip_leb r
        | n -> unsupported "instruction 0xFC %d" n)
    | 0xFD -> (
        match uleb r with
        | n when n <= 11 || n = 92 || n = 93 -> ignore (memarg r)
        | 12 | 13 -> r.pos <- r.pos + 16
        | n when n >= 21 && n <= 34 -> r.pos <- r.pos + 1
        | n when n >= 84 && n <= 91 -> ignore (memarg r); r.pos <- r.pos + 1
        | _ -> ())
    | 0xFE ->
        flush start;
        incr count;
        (match uleb r with
        | 0x03 -> ignore (byte r)
        | n when n >= 0x10 && n <= 0x1D ->
            let m = memarg r in
            Buffer.add_char out (Char.chr plain.(n - 0x10));
            Buffer.add_string out m
        | n when n <= 0x02 || (n >= 0x1E && n <= 0x4E) ->
            let m = memarg r in
            Buffer.add_char out '\x10';
            add_uleb out (call n m)
        | n -> unsupported "atomic instruction 0xFE 0x%02X" n);
        copied := r.pos
    | op -> unsupported "instruction 0x%02X" op
  done;
  flush body_end;
  !count

(* The module [s] without atomic instructions, and how many there were. *)
let lower s =
  if String.length s < 8 || String.sub s 0 4 <> "\000asm" then unsupported "not a wasm module";
  let r = { s; pos = 8 } in
  let sections = ref [] in
  while r.pos < String.length s do
    let id = byte r in
    let size = uleb r in
    sections := (id, r.pos, r.pos + size) :: !sections;
    r.pos <- r.pos + size
  done;
  let sections = List.rev !sections in
  let section id = Compat.find_map (fun (i, a, b) -> if i = id then Some (a, b) else None) sections in
  let count_at a = r.pos <- a; uleb r in
  (* the types (functions only, not those of the GC proposal), the imported
     functions, the defined ones; the memories are not shared *)
  let types =
    match section 1 with
    | None -> 0
    | Some (a, _) ->
        let n = count_at a in
        for _ = 1 to n do
          if byte r <> 0x60 then unsupported "a type that is not a function type";
          for _ = 1 to uleb r do valtype r done;
          for _ = 1 to uleb r do valtype r done
        done;
        n
  in
  let imported_funcs =
    match section 2 with
    | None -> 0
    | Some (a, _) ->
        let funcs = ref 0 in
        for _ = 1 to count_at a do
          r.pos <- r.pos + uleb r; r.pos <- r.pos + uleb r;
          match byte r with
          | 0 -> incr funcs; skip_leb r
          | 1 -> valtype r; limits r
          | 2 -> limits r
          | 3 -> valtype r; ignore (byte r)
          | _ -> ignore (byte r); skip_leb r
        done;
        !funcs
  in
  (match section 5 with Some (a, _) -> for _ = 1 to count_at a do limits r done | None -> ());
  let defined = match section 3 with Some (a, _) -> count_at a | None -> 0 in
  (* the code, and the functions added *)
  let helpers = Hashtbl.create 16 and added = ref [] and signatures = ref [] in
  let call n m =
    match Hashtbl.find_opt helpers (n, m) with
    | Some i -> i
    | None ->
        let i = imported_funcs + defined + List.length !added in
        let ((params, results, _, _) as h) = helper n m in
        if not (List.mem (params, results) !signatures) then signatures := !signatures @ [ (params, results) ];
        Hashtbl.add helpers (n, m) i;
        added := !added @ [ h ];
        i
  in
  let code = Buffer.create (String.length s) and lowered = ref 0 in
  (match section 10 with
  | None -> ()
  | Some (a, _) ->
      let bodies = count_at a in
      for _ = 1 to bodies do
        let size = uleb r in
        let body_end = r.pos + size in
        let body = Buffer.create size in
        lowered := !lowered + lower_body r body_end body ~call;
        add_uleb code (Buffer.length body);
        Buffer.add_buffer code body
      done);
  if !lowered = 0 then (s, 0)
  else if !added <> [] && (section 1 = None || section 3 = None) then unsupported "no type or function section"
  else
    let vec_with a b items =
      let out = Buffer.create (b - a + 64) in
      let n = count_at a in
      add_uleb out (n + List.length items);
      Buffer.add_string out (String.sub s r.pos (b - r.pos));
      List.iter (Buffer.add_string out) items;
      Buffer.contents out
    in
    let encode f = let b = Buffer.create 16 in f b; Buffer.contents b in
    let type_index (params, results, _, _) =
      let rec go i = function x :: l -> if x = (params, results) then i else go (i + 1) l | [] -> assert false in
      types + go 0 !signatures
    in
    let valtypes b l = add_uleb b (List.length l); List.iter (fun t -> Buffer.add_char b (Char.chr t)) l in
    let new_types = List.map (fun (p, res) -> encode (fun b -> Buffer.add_char b '\x60'; valtypes b p; valtypes b res)) !signatures in
    let new_funcs = List.map (fun h -> encode (fun b -> add_uleb b (type_index h))) !added in
    let new_bodies =
      List.map
        (fun (_, _, locals, c) ->
          let body = encode (fun b -> add_uleb b (List.length locals); List.iter (fun t -> add_uleb b 1; Buffer.add_char b (Char.chr t)) locals; Buffer.add_string b c) in
          encode (fun b -> add_uleb b (String.length body); Buffer.add_string b body))
        !added
    in
    let payload (id, a, b) =
      match id with
      | 1 -> vec_with a b new_types
      | 3 -> vec_with a b new_funcs
      | 10 ->
          let n = count_at a in
          encode (fun out -> add_uleb out (n + List.length new_bodies); Buffer.add_buffer out code; List.iter (Buffer.add_string out) new_bodies)
      | _ -> String.sub s a (b - a)
    in
    let out = Buffer.create (String.length s + 1024) in
    Buffer.add_string out (String.sub s 0 8);
    List.iter
      (fun ((id, _, _) as sec) ->
        let p = payload sec in
        Buffer.add_char out (Char.chr id);
        add_uleb out (String.length p);
        Buffer.add_string out p)
      sections;
    (Buffer.contents out, !lowered)

(* Lowers the module in [path] in place; the number of atomic instructions
   replaced. *)
let file path =
  match lower (Compat.read_file path) with
  | exception Unsupported why -> failwith (path ^ ": cannot remove its atomic instructions: " ^ why)
  | _, 0 -> 0
  | s, n -> Compat.write_file path s; n
