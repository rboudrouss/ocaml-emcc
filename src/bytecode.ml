(* Reading and rewriting OCaml bytecode executables.

   Layout (unchanged since 4.0x, still true in 5.x):

     [header]  section_1 ... section_n  table  trailer

   - table:   n entries of (name: 4 chars, length: int32 BE)
   - trailer: n (int32 BE) then the 12-byte magic "Caml1999X0NN"

   The header (a #! line or a launcher) is not part of any section. *)

type section = { name : string; data : string }

type t = { magic : string; sections : section list }

let trailer_size = 16

let read_file = Compat.read_file

let int32_be s pos = Int32.to_int (Compat.get_int32_be s pos)

let parse path =
  let s = read_file path in
  let len = String.length s in
  if len < trailer_size then failwith (path ^ ": not a bytecode executable");
  let magic = String.sub s (len - 12) 12 in
  if not (String.length magic = 12 && String.sub magic 0 9 = "Caml1999X") then
    failwith (path ^ ": not a bytecode executable (bad magic)");
  let n = int32_be s (len - trailer_size) in
  let table_pos = len - trailer_size - (8 * n) in
  let entries =
    List.init n (fun i ->
        let p = table_pos + (8 * i) in
        (String.sub s p 4, int32_be s (p + 4)))
  in
  let total = List.fold_left (fun acc (_, l) -> acc + l) 0 entries in
  let pos = ref (table_pos - total) in
  let sections =
    List.map
      (fun (name, l) ->
        let data = String.sub s !pos l in
        pos := !pos + l;
        { name; data })
      entries
  in
  { magic; sections }

let section t name =
  Compat.find_map (fun s -> if s.name = name then Some s.data else None) t.sections

(* NUL-separated string lists (PRIM, DLLS, DLPT). *)
let split_nul data = String.split_on_char '\000' data |> List.filter (( <> ) "")

let primitives t = Option.fold ~none:[] ~some:split_nul (section t "PRIM")
let dlls t = Option.fold ~none:[] ~some:split_nul (section t "DLLS")
let dll_paths t = Option.fold ~none:[] ~some:split_nul (section t "DLPT")

(* Write a copy without the given sections.  Used to drop DLLS/DLPT: the
   stubs are linked statically, so the runtime must not try to dlopen
   anything (it would abort with "cannot load shared library"). *)
let write ?(drop = []) t path =
  let sections = List.filter (fun s -> not (List.mem s.name drop)) t.sections in
  Compat.with_out_bin path (fun oc ->
      List.iter (fun s -> output_string oc s.data) sections;
      let b = Bytes.create 8 in
      List.iter
        (fun s ->
          Bytes.blit_string s.name 0 b 0 4;
          Bytes.set_int32_be b 4 (Int32.of_int (String.length s.data));
          output_bytes oc b)
        sections;
      let b = Bytes.create 4 in
      Bytes.set_int32_be b 0 (Int32.of_int (List.length sections));
      output_bytes oc b;
      output_string oc t.magic)

(* "dllzarith" -> "zarith": the library part of a stub DLL name, which is
   also the name of the static archive (libzarith.a). *)
let lib_of_dll d =
  let d = Filename.basename d in
  let d = if Filename.check_suffix d ".so" then Filename.chop_suffix d ".so" else d in
  if String.length d > 3 && String.sub d 0 3 = "dll" then
    String.sub d 3 (String.length d - 3)
  else d

(* ------------------------------------------------------------------ code *)

(* Opcodes, in order (runtime/caml/instruct.h).  OCaml 5 appended the
   effect instructions; the numbering of the others is unchanged since 4.x. *)
let opcodes =
  [| "ACC0"; "ACC1"; "ACC2"; "ACC3"; "ACC4"; "ACC5"; "ACC6"; "ACC7"; "ACC"; "PUSH";
     "PUSHACC0"; "PUSHACC1"; "PUSHACC2"; "PUSHACC3"; "PUSHACC4"; "PUSHACC5"; "PUSHACC6";
     "PUSHACC7"; "PUSHACC"; "POP"; "ASSIGN"; "ENVACC1"; "ENVACC2"; "ENVACC3"; "ENVACC4";
     "ENVACC"; "PUSHENVACC1"; "PUSHENVACC2"; "PUSHENVACC3"; "PUSHENVACC4"; "PUSHENVACC";
     "PUSH_RETADDR"; "APPLY"; "APPLY1"; "APPLY2"; "APPLY3"; "APPTERM"; "APPTERM1";
     "APPTERM2"; "APPTERM3"; "RETURN"; "RESTART"; "GRAB"; "CLOSURE"; "CLOSUREREC";
     "OFFSETCLOSUREM3"; "OFFSETCLOSURE0"; "OFFSETCLOSURE3"; "OFFSETCLOSURE";
     "PUSHOFFSETCLOSUREM3"; "PUSHOFFSETCLOSURE0"; "PUSHOFFSETCLOSURE3"; "PUSHOFFSETCLOSURE";
     "GETGLOBAL"; "PUSHGETGLOBAL"; "GETGLOBALFIELD"; "PUSHGETGLOBALFIELD"; "SETGLOBAL";
     "ATOM0"; "ATOM"; "PUSHATOM0"; "PUSHATOM"; "MAKEBLOCK"; "MAKEBLOCK1"; "MAKEBLOCK2";
     "MAKEBLOCK3"; "MAKEFLOATBLOCK"; "GETFIELD0"; "GETFIELD1"; "GETFIELD2"; "GETFIELD3";
     "GETFIELD"; "GETFLOATFIELD"; "SETFIELD0"; "SETFIELD1"; "SETFIELD2"; "SETFIELD3";
     "SETFIELD"; "SETFLOATFIELD"; "VECTLENGTH"; "GETVECTITEM"; "SETVECTITEM";
     "GETBYTESCHAR"; "SETBYTESCHAR"; "BRANCH"; "BRANCHIF"; "BRANCHIFNOT"; "SWITCH";
     "BOOLNOT"; "PUSHTRAP"; "POPTRAP"; "RAISE"; "CHECK_SIGNALS"; "C_CALL1"; "C_CALL2";
     "C_CALL3"; "C_CALL4"; "C_CALL5"; "C_CALLN"; "CONST0"; "CONST1"; "CONST2"; "CONST3";
     "CONSTINT"; "PUSHCONST0"; "PUSHCONST1"; "PUSHCONST2"; "PUSHCONST3"; "PUSHCONSTINT";
     "NEGINT"; "ADDINT"; "SUBINT"; "MULINT"; "DIVINT"; "MODINT"; "ANDINT"; "ORINT";
     "XORINT"; "LSLINT"; "LSRINT"; "ASRINT"; "EQ"; "NEQ"; "LTINT"; "LEINT"; "GTINT";
     "GEINT"; "OFFSETINT"; "OFFSETREF"; "ISINT"; "GETMETHOD"; "BEQ"; "BNEQ"; "BLTINT";
     "BLEINT"; "BGTINT"; "BGEINT"; "ULTINT"; "UGEINT"; "BULTINT"; "BUGEINT"; "GETPUBMET";
     "GETDYNMET"; "STOP"; "EVENT"; "BREAK"; "RERAISE"; "RAISE_NOTRACE"; "GETSTRINGCHAR";
     "PERFORM"; "RESUME"; "RESUMETERM"; "REPERFORMTERM" |]

let opcode name =
  let rec go i = if opcodes.(i) = name then i else go (i + 1) in
  go 0

(* Operand counts (runtime/fix_code.c, caml_init_opcode_nargs). *)
let nargs =
  let t = Array.make (Array.length opcodes) 0 in
  List.iter (fun n -> t.(opcode n) <- 1)
    [ "PUSHACC"; "ACC"; "POP"; "ASSIGN"; "PUSHENVACC"; "ENVACC"; "PUSH_RETADDR"; "APPLY";
      "APPTERM1"; "APPTERM2"; "APPTERM3"; "RETURN"; "GRAB"; "PUSHGETGLOBAL"; "GETGLOBAL";
      "SETGLOBAL"; "PUSHATOM"; "ATOM"; "MAKEBLOCK1"; "MAKEBLOCK2"; "MAKEBLOCK3";
      "MAKEFLOATBLOCK"; "GETFIELD"; "GETFLOATFIELD"; "SETFIELD"; "SETFLOATFIELD"; "BRANCH";
      "BRANCHIF"; "BRANCHIFNOT"; "PUSHTRAP"; "C_CALL1"; "C_CALL2"; "C_CALL3"; "C_CALL4";
      "C_CALL5"; "CONSTINT"; "PUSHCONSTINT"; "OFFSETINT"; "OFFSETREF"; "OFFSETCLOSURE";
      "PUSHOFFSETCLOSURE"; "RESUMETERM"; "REPERFORMTERM" ];
  List.iter (fun n -> t.(opcode n) <- 2)
    [ "APPTERM"; "CLOSURE"; "PUSHGETGLOBALFIELD"; "GETGLOBALFIELD"; "MAKEBLOCK"; "C_CALLN";
      "BEQ"; "BNEQ"; "BLTINT"; "BLEINT"; "BGTINT"; "BGEINT"; "BULTINT"; "BUGEINT";
      "GETPUBMET" ];
  t

(* How the bytecode calls each primitive, by index in PRIM: k for C_CALLk
   (k <= 5, C signature value(value, ...)), -1 for C_CALLN (value(value *,
   int)).  Primitives that are never called directly are absent. *)
let call_arities t =
  let tbl = Hashtbl.create 512 in
  match section t "CODE" with
  | None -> tbl
  | Some code ->
      let n = String.length code / 4 in
      let word i = Int32.to_int (Compat.get_int32_le code (4 * i)) in
      let c_call1 = opcode "C_CALL1" and c_calln = opcode "C_CALLN" in
      let switch = opcode "SWITCH" and closurerec = opcode "CLOSUREREC" in
      let i = ref 0 in
      (try
         while !i < n do
           let op = word !i in
           if op < 0 || op >= Array.length opcodes then raise Exit;
           if op >= c_call1 && op < c_calln then
             Hashtbl.replace tbl (word (!i + 1)) (op - c_call1 + 1)
           else if op = c_calln then Hashtbl.replace tbl (word (!i + 2)) (-1);
           if op = switch then (
             let sizes = word (!i + 1) land 0xFFFFFFFF in
             i := !i + 2 + (sizes land 0xFFFF) + (sizes lsr 16))
           else if op = closurerec then i := !i + 3 + word (!i + 1)
           else i := !i + 1 + nargs.(op)
         done
       with Exit -> ());
      tbl

(* ------------------------------------------------------------- literals *)

(* Integers of the program that do not fit in 31 bits.

   The bytecode compiler only emits 31-bit immediates (CONSTINT & co,
   Instruct.immed_min/max), every other integer constant goes to the DATA
   section, which the 64-bit marshaller writes with CODE_INT64 (extern.c).
   A 32-bit runtime refuses those at startup ("input_value: integer too
   large"), so scanning DATA finds exactly the literals that break wasm32.

   The marshalled stream is walked item by item: blocks only have a header,
   their fields are the following items, so no structure has to be kept. *)
type scan = Found of int64 list | Unknown of string

let large_literals t =
  match section t "DATA" with
  | None -> Found []
  | Some s ->
      let len = String.length s in
      let u8 i = Char.code s.[i] in
      let be32 i = Int32.to_int (Compat.get_int32_be s i) land 0xFFFFFFFF in
      let be64 i = Int64.to_int (Compat.get_int64_be s i) in
      let magic = Compat.get_int32_be s 0 in
      let start, stop =
        if magic = 0x8495A6BEl then (20, 20 + be32 4)
        else if magic = 0x8495A6BFl then (32, 32 + be64 8)
        else (-1, 0)
      in
      if start < 0 then Unknown "unknown marshal format in DATA"
      else
        let found = ref [] in
        let rec cstring i = if s.[i] = '\000' then i + 1 else cstring (i + 1) in
        let rec go i =
          if i >= stop || i >= len then Found (List.rev !found)
          else
            let c = u8 i in
            if c >= 0x80 then go (i + 1) (* small block *)
            else if c >= 0x40 then go (i + 1) (* small int *)
            else if c >= 0x20 then go (i + 1 + (c land 0x1F)) (* small string *)
            else
              match c with
              | 0x00 -> go (i + 2) (* INT8 *)
              | 0x01 -> go (i + 3) (* INT16 *)
              | 0x02 -> go (i + 5) (* INT32 *)
              | 0x03 ->
                  found := Compat.get_int64_be s (i + 1) :: !found;
                  go (i + 9) (* INT64 *)
              | 0x04 -> go (i + 2) (* SHARED8 *)
              | 0x05 -> go (i + 3) (* SHARED16 *)
              | 0x06 -> go (i + 5) (* SHARED32 *)
              | 0x14 -> go (i + 9) (* SHARED64 *)
              | 0x08 -> go (i + 5) (* BLOCK32 *)
              | 0x13 -> go (i + 9) (* BLOCK64 *)
              | 0x09 -> go (i + 2 + u8 (i + 1)) (* STRING8 *)
              | 0x0A -> go (i + 5 + be32 (i + 1)) (* STRING32 *)
              | 0x15 -> go (i + 9 + be64 (i + 1)) (* STRING64 *)
              | 0x0B | 0x0C -> go (i + 9) (* DOUBLE *)
              | 0x0D | 0x0E -> go (i + 2 + (8 * u8 (i + 1))) (* DOUBLE_ARRAY8 *)
              | 0x0F | 0x07 -> go (i + 5 + (8 * be32 (i + 1))) (* DOUBLE_ARRAY32 *)
              | 0x16 | 0x17 -> go (i + 9 + (8 * be64 (i + 1))) (* DOUBLE_ARRAY64 *)
              | 0x10 -> go (i + 1 + 4 + 16) (* CODEPOINTER: offset + digest *)
              | 0x11 -> go (i + 5) (* INFIXPOINTER *)
              | 0x18 ->
                  (* CUSTOM_LEN: id, size32, size64, data *)
                  let j = cstring (i + 1) in
                  go (j + 12 + be64 (j + 4))
              | 0x19 -> (
                  (* CUSTOM_FIXED: size known to the custom ops only *)
                  let j = cstring (i + 1) in
                  match String.sub s (i + 1) (j - i - 2) with
                  | "_i" -> go (j + 4)
                  | "_j" -> go (j + 8)
                  | "_n" -> go (j + 9)
                  | id -> Unknown ("custom block " ^ id ^ " in DATA"))
              | c -> Unknown (Printf.sprintf "marshal code 0x%02x in DATA" c)
        in
        (try go start with Invalid_argument _ -> Unknown "truncated DATA section")

let fits_31 n = Int64.compare n (-0x40000000L) >= 0 && Int64.compare n 0x3FFFFFFFL <= 0
