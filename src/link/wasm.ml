(* Reading wasm modules: the imports of a linked module, the function
   symbols of a relocatable object (the input of wasm-ld). *)

(* A function type: parameter and result types ("i32", "i64", "f32"...) *)
type signature = { params : string list; results : string list }

type symbol = {
  name : string;
  defined : bool;
  local : bool;  (** static: not visible to the other objects *)
  signature : signature;
}

(* The sections of a wasm module, with a reader of its contents. *)
let sections ~what s f =
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
  let r = (byte, uleb, name, pos) in
  let rec go () =
    if !pos < len then (
      let id = byte () in
      let size = uleb () in
      let next = !pos + size in
      f r id next;
      pos := next;
      go ())
  in
  if len < 8 || String.sub s 0 4 <> "\000asm" then failwith (what ^ ": not a wasm module");
  try go () with Failure _ | Invalid_argument _ -> failwith (what ^ ": malformed wasm module")

let limits (byte, uleb, _, _) =
  let flags = byte () in
  ignore (uleb ());
  if flags land 1 <> 0 then ignore (uleb ())

let reftype (byte, uleb, _, _) = match byte () with 0x63 | 0x64 -> ignore (uleb ()) | _ -> ()

(* An import: module, field, and the type index of a function. *)
let import ((byte, uleb, name, _) as r) =
  let m = name () in
  let f = name () in
  let ty =
    match byte () with
    | 0 -> Some (uleb ())
    | 1 -> reftype r; limits r; None (* table *)
    | 2 -> limits r; None (* memory *)
    | 3 -> reftype r; ignore (byte ()); None (* global: type, mutability *)
    | _ -> ignore (byte ()); ignore (uleb ()); None (* tag: attribute, type index *)
  in
  (m, f, ty)

let vec (_, uleb, _, _) f = List.init (uleb ()) (fun _ -> f ())

(* The imports of a wasm module (module name, field name), read from its
   import section: what a standalone OUT.wasm needs from its host. *)
let imports path =
  let acc = ref [] in
  sections ~what:path (Compat.read_file path) (fun r id _ ->
      if id = 2 then acc := List.map (fun (m, f, _) -> (m, f)) (vec r (fun () -> import r)));
  !acc

let valtype (byte, _, _, _) =
  match byte () with
  | 0x7f -> "i32"
  | 0x7e -> "i64"
  | 0x7d -> "f32"
  | 0x7c -> "f64"
  | 0x7b -> "v128"
  | b -> Printf.sprintf "ref:%x" b

(* The function symbols of a relocatable object, from the symbol table of
   its "linking" section (tool-conventions/Linking.md), with the types of
   the functions (defined: function section, undefined: imports). *)
let functions ~what s =
  let types = ref [||] and imported = ref [] and defined = ref [] and syms = ref [] in
  sections ~what s (fun ((byte, uleb, name, pos) as r) id next ->
      match id with
      | 1 ->
          types :=
            Array.of_list
              (vec r (fun () ->
                   if byte () <> 0x60 then failwith "not a function type";
                   let params = vec r (fun () -> valtype r) in
                   let results = vec r (fun () -> valtype r) in
                   { params; results }))
      | 2 -> imported := List.filter_map (fun (_, f, ty) -> Option.map (fun t -> (f, t)) ty) (vec r (fun () -> import r))
      | 3 -> defined := vec r uleb
      | 0 when name () = "linking" ->
          ignore (uleb ()) (* version *);
          let funcs = Array.of_list (List.map snd !imported @ !defined) in
          let import_names = Array.of_list (List.map fst !imported) in
          while !pos < next do
            let kind = byte () in
            let size = uleb () in
            let sub_end = !pos + size in
            (* WASM_SYMBOL_TABLE *)
            if kind = 8 then
              syms :=
                List.filter_map Fun.id
                  (vec r (fun () ->
                       let kind = byte () and flags = uleb () in
                       let undefined = flags land 0x10 <> 0 and explicit_name = flags land 0x40 <> 0 in
                       match kind with
                       | 0 (* function *) ->
                           let index = uleb () in
                           let name =
                             if undefined && not explicit_name then import_names.(index) else name ()
                           in
                           let signature = !types.(funcs.(index)) in
                           Some { name; defined = not undefined; local = flags land 0x2 <> 0; signature }
                       | 1 (* data *) ->
                           ignore (name ());
                           if not undefined then (ignore (uleb ()); ignore (uleb ()); ignore (uleb ()));
                           None
                       | 3 (* section *) ->
                           ignore (uleb ());
                           None
                       | _ (* global, tag, table *) ->
                           ignore (uleb ());
                           if (not undefined) || explicit_name then ignore (name ());
                           None));
            pos := sub_end
          done
      | _ -> ());
  !syms
