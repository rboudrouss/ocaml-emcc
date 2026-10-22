(* tsdl: SDL2 through ctypes-foreign (and C stubs); without video *)
open Tsdl
let ok = function Ok x -> x | Error (`Msg m) -> failwith m
let () =
  ok (Sdl.init Sdl.Init.(timer + events));
  let (maj, min, _) = Sdl.get_version () in
  Printf.printf "SDL %d.%d\n" maj min;
  Printf.eprintf "platform: %s\n" (Sdl.get_platform ());
  let t0 = Sdl.get_ticks () in
  Sdl.delay 20l;
  Printf.printf "delay ok: %b\n" (Int32.sub (Sdl.get_ticks ()) t0 >= 15l);
  let s = ok (Sdl.create_rgb_surface ~w:8 ~h:4 ~depth:32 0xff0000l 0xff00l 0xffl 0xff000000l) in
  ok (Sdl.fill_rect s (Some (Sdl.Rect.create ~x:2 ~y:1 ~w:3 ~h:2)) 0xff00ff00l);
  let px = Sdl.get_surface_pixels s Bigarray.int32 in
  let n = ref 0 in
  for i = 0 to Bigarray.Array1.dim px - 1 do if px.{i} = 0xff00ff00l then incr n done;
  Printf.printf "surface %dx%d pitch %d, filled %d\n" (fst (Sdl.get_surface_size s)) (snd (Sdl.get_surface_size s)) (Sdl.get_surface_pitch s) !n;
  Sdl.free_surface s;
  let e = Sdl.Event.create () in
  ignore (ok (Sdl.push_event (let u = Sdl.Event.create () in Sdl.Event.(set u typ user_event); u)));
  Printf.printf "event polled: %b\n" (Sdl.poll_event (Some e) && Sdl.Event.(get e typ) = Sdl.Event.user_event);
  let rw = ok (Sdl.rw_from_mem (Bytes.of_string "abc, from memory")) in
  Printf.printf "rw: %s\n" (ok (Sdl.load_file_rw rw true));
  Printf.printf "clipboard-free hint: %b\n" (Sdl.set_hint "SDL_HINT_TEST" "1");
  Sdl.quit ();
  print_endline "done"
