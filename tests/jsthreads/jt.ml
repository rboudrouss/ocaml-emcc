(* js_of_ocaml with threads: JavaScript belongs to the main thread, the
   others get an exception; the GC of another thread finalizes JavaScript
   values; once main returned, the threads go on between callbacks *)
open Js_of_ocaml

let upper s = Js.to_string (Js.Unsafe.meth_call (Js.string s) "toUpperCase" [||])

let set_timeout f ms =
  ignore (Js.Unsafe.fun_call (Js.Unsafe.js_expr "setTimeout") [| Js.Unsafe.inject (Js.wrap_callback f); Js.Unsafe.inject ms |])

let () =
  print_endline ("main: " ^ upper "main");
  let t =
    Thread.create
      (fun () ->
        match upper "thread" with
        | s -> print_endline ("thread: " ^ s)
        | exception Failure m -> print_endline ("thread: " ^ m))
      ()
  in
  Thread.join t;
  let vals = ref (List.init 1000 (fun i -> Js.string (string_of_int i))) in
  vals := [];
  let t = Thread.create (fun () -> for _ = 1 to 3 do Gc.full_major () done) () in
  Thread.join t;
  print_endline ("main again: " ^ upper "after the collections");
  let m = Mutex.create () and steps = ref 0 in
  ignore
    (Thread.create
       (fun () ->
         for _ = 1 to 3 do
           Thread.delay 0.02;
           Mutex.lock m;
           incr steps;
           Mutex.unlock m
         done)
       ());
  let rec poll () =
    Mutex.lock m;
    let n = !steps in
    Mutex.unlock m;
    if n < 3 then set_timeout poll 20
    else (
      print_endline ("callback: the thread made its 3 steps, " ^ upper "after main");
      print_endline "done")
  in
  set_timeout poll 20;
  print_endline "main returns"
