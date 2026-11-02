(* js_of_ocaml's primitives: the program runs in node, the output is
   compared to expected.txt *)
open Js_of_ocaml

let p fmt = Printf.printf (fmt ^^ "\n%!")

let () =
  (* properties, methods, strings *)
  let o = object%js
    val x = 42
    val mutable name = Js.string "héllo wörld"
    method add y = Js.number_of_float (float_of_int y +. 0.5)
  end in
  p "x=%d name=%s" o##.x (Js.to_string o##.name);
  o##.name := Js.string "changed";
  p "name=%s add=%g" (Js.to_string o##.name) (Js.float_of_number (o##add 2));
  let s = Js.string "a,b,c" in
  let parts = Js.to_array (Js.str_array (s##split (Js.string ","))) in
  p "split: %s" (String.concat "|" (Array.to_list (Array.map Js.to_string parts)));
  p "length=%d upper=%s" s##.length (Js.to_string s##toUpperCase);
  p "bytestring=%S" (Js.to_bytestring (Js.bytestring "\xe9\x00z"));
  (* numbers, booleans, null *)
  let math = Js.Unsafe.global##._Math in
  p "max=%d pow=%g" (math##max 3 9 4) (Js.float_of_number (math##pow (Js.number_of_float 2.) (Js.number_of_float 0.5)));
  p "bool=%b %b" (Js.to_bool Js._true) (Js.to_bool (Js.bool false));
  p "null: %b %b" (Js.Opt.test Js.null) (Js.Opt.test (Js.some o));
  p "undefined: %b" (Js.Optdef.test (Js.Unsafe.get o "nope" : int Js.optdef));
  p "typeof=%s instanceof=%b" (Js.to_string (Js.typeof o)) (Js.instanceof (new%js Js.array_empty) Js.array_empty);
  p "int32=%ld" (Js.to_int32 (Js.Unsafe.js_expr "2**31 + 5"));
  (* arrays *)
  let a = Js.array [| 1; 2; 3 |] in
  ignore (a##push 4);
  p "array: %d [%s]" a##.length (String.concat ";" (Array.to_list (Array.map string_of_int (Js.to_array a))));
  (* callbacks *)
  let doubled = a##map (Js.wrap_callback (fun x _ _ -> 2 * x)) in
  p "map: [%s]" (String.concat ";" (Array.to_list (Array.map string_of_int (Js.to_array doubled))));
  let sum = a##reduce_init (Js.wrap_callback (fun acc x _ _ -> acc + x)) 0 in
  p "reduce: %d" sum;
  let f : (int -> int -> int) Js.callback = Js.wrap_callback (fun x y -> x * 10 + y) in
  p "call: %d" (Js.Unsafe.fun_call f [| Js.Unsafe.inject 4; Js.Unsafe.inject 2 |]);
  let u = Js.Unsafe.callback (fun x y -> x - y) in
  p "unsafe callback: %d" (Js.Unsafe.fun_call u [| Js.Unsafe.inject 9; Js.Unsafe.inject 4 |]);
  let m = Js.Unsafe.obj [| ("v", Js.Unsafe.inject 7) |] in
  Js.Unsafe.set m "get" (Js.wrap_meth_callback (fun this k -> (Js.Unsafe.get this "v" : int) + k));
  p "meth callback: %d" (Js.Unsafe.meth_call m "get" [| Js.Unsafe.inject 100 |]);
  (* OCaml values through JavaScript *)
  let r = ref 0 in
  Js.Unsafe.set m "ocaml" r;
  (Js.Unsafe.get m "ocaml" : int ref) := 5;
  p "opaque: %d same=%b" !r ((Js.Unsafe.get m "ocaml" : int ref) == r);
  (* exceptions *)
  (try ignore (Js.Unsafe.js_expr "(function () { throw new TypeError('boom') })()")
   with Js_error.Exn e -> p "js error: %s / %s" (Js_error.name e) (Js_error.message e));
  (try ignore (Js.Unsafe.js_expr "(function () { throw 'a string' })()")
   with Failure s -> p "failure: %s" s);
  let raiser = Js.wrap_callback (fun () -> raise Not_found) in
  (try ignore (Js.Unsafe.fun_call raiser [||]) with Not_found -> p "Not_found through JavaScript");
  (try Js_error.raise_ (Js_error.of_error (new%js Js.error_constr (Js.string "mine")))
   with Js_error.Exn e -> p "raised: %s" (Js_error.message e));
  (* typed arrays and bigarrays *)
  let ba = Bigarray.Array1.of_array Bigarray.int16_signed Bigarray.c_layout [| 1; -2; 300 |] in
  let ta = Typed_array.from_genarray Typed_array.Int16_signed (Bigarray.genarray_of_array1 ba) in
  p "typed: %d %d" ta##.length (Typed_array.unsafe_get ta 1);
  let back = Bigarray.array1_of_genarray (Typed_array.to_genarray ta) in
  p "back: %d %d" (Bigarray.Array1.dim back) back.{2};
  let u8 = Typed_array.Bytes.to_uint8Array (Bytes.of_string "abc") in
  p "bytes: %s %s" (Bytes.to_string (Typed_array.Bytes.of_uint8Array u8))
    (Typed_array.String.of_arrayBuffer u8##.buffer);
  (* JSON, globals *)
  let j = Json.output (1, "a", [| 2.5 |]) in
  p "json: %s" (Js.to_string j);
  p "parse: %d" (Js._JSON##parse (Js.string "{\"a\": 12}"))##.a;
  (* the event loop goes on after the main program *)
  let n = ref 0 in
  let rec tick () =
    incr n;
    if !n < 3 then ignore (Dom_html.setTimeout tick 1.)
    else p "timeouts: %d" !n
  in
  ignore (Dom_html.setTimeout tick 1.);
  ignore (Js.Unsafe.meth_call (Js.Unsafe.js_expr "Promise.resolve(3)") "then"
            [| Js.Unsafe.inject (Js.wrap_callback (fun x -> p "promise: %d" x)) |]);
  p "main done"
