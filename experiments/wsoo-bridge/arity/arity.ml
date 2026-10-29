(* arity.exe PROG.bc: "name arity" for each primitive that PROG.bc calls,
   with its argument count (also for C_CALLN, unlike Bytecode.call_arities).
   Built by build.sh with src/{compat,str_util,bytecode}.ml. *)

let () =
  let t = Bytecode.parse Sys.argv.(1) in
  let prims =
    match Bytecode.section t "PRIM" with
    | Some s -> Array.of_list (List.filter (( <> ) "") (String.split_on_char '\000' s))
    | None -> [||]
  in
  let code = Option.get (Bytecode.section t "CODE") in
  let n = String.length code / 4 in
  let word i = Int32.to_int (Compat.get_int32_le code (4 * i)) in
  let op = Bytecode.opcode in
  let tbl = Hashtbl.create 64 in
  let i = ref 0 in
  (try
     while !i < n do
       let o = word !i in
       if o < 0 || o >= Array.length Bytecode.opcodes then raise Exit;
       if o >= op "C_CALL1" && o < op "C_CALLN" then
         Hashtbl.replace tbl (word (!i + 1)) (o - op "C_CALL1" + 1)
       else if o = op "C_CALLN" then Hashtbl.replace tbl (word (!i + 2)) (word (!i + 1));
       if o = op "SWITCH" then (
         let s = word (!i + 1) land 0xFFFFFFFF in
         i := !i + 2 + (s land 0xFFFF) + (s lsr 16))
       else if o = op "CLOSUREREC" then i := !i + 3 + word (!i + 1)
       else i := !i + 1 + Bytecode.nargs.(o)
     done
   with Exit -> ());
  Hashtbl.iter (fun k a -> Printf.printf "%s %d\n" prims.(k) a) tbl
