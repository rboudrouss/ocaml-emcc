(* Reading ar archives (lib*.a): GNU and BSD member names. *)

(* The members of an archive in order: (name, contents), without the
   symbol and name tables.  None if it is not an archive. *)
let members file =
  match Compat.read_file file with
  | exception Sys_error _ -> None
  | s when not (Str_util.starts_with ~prefix:"!<arch>\n" s) -> None
  | s ->
      let n = String.length s in
      let field off len = String.trim (String.sub s off len) in
      let rec go pos names acc =
        if pos + 60 > n then List.rev acc
        else
          let name = field pos 16 in
          let size = int_of_string (field (pos + 48) 10) in
          let data = pos + 60 in
          let next = data + size + (size land 1) in
          let contents = String.sub s data (min size (n - data)) in
          if name = "//" then go next contents acc
          else if name = "/" || name = "/SYM64/" || Str_util.starts_with ~prefix:"__.SYMDEF" name then go next names acc
          else if Str_util.starts_with ~prefix:"#1/" name then
            (* BSD: the name before the contents *)
            let l = int_of_string (String.sub name 3 (String.length name - 3)) in
            let real = String.sub contents 0 l in
            let real = match String.index_opt real '\000' with Some i -> String.sub real 0 i | None -> real in
            go next names ((real, String.sub contents l (String.length contents - l)) :: acc)
          else if String.length name > 1 && name.[0] = '/' then
            (* GNU: an offset in the name table, the name ends with "/\n" *)
            let off = int_of_string (String.sub name 1 (String.length name - 1)) in
            let e = match String.index_from_opt names off '\n' with Some e -> e | None -> String.length names in
            let real = String.sub names off (e - off) in
            let real = if Filename.check_suffix real "/" then Filename.chop_suffix real "/" else real in
            go next names ((real, contents) :: acc)
          else
            let name = if Filename.check_suffix name "/" then Filename.chop_suffix name "/" else name in
            go next names ((name, contents) :: acc)
      in
      (try Some (go 8 "" []) with Failure _ | Invalid_argument _ -> None)

let names file = match members file with Some m -> List.map fst m | None -> []

(* Whether the (first) object of an archive is a wasm one: true when it
   cannot be told *)
let is_wasm file =
  match members file with
  | None -> true
  | Some m -> (
      match List.find_opt (fun (n, _) -> Filename.check_suffix n ".o") m with
      | Some (_, c) -> String.length c >= 4 && String.sub c 0 4 = "\000asm"
      | None -> true)
