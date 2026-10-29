(* raylib: what needs no window (images on the CPU, colors, collisions,
   vectors, text), so that it runs under node.  Image starts with a
   pointer: its fields are read through the target's layout. *)
open Raylib

let () =
  let img = gen_image_color 8 6 Color.blue in
  Printf.printf "image %dx%d mipmaps %d\n" (Image.width img) (Image.height img) (Image.mipmaps img);
  let p = Ctypes.allocate Image.t img in
  image_draw_pixel p 2 3 Color.red;
  image_draw_rectangle p 4 0 3 2 Color.green;
  image_flip_horizontal p;
  image_resize p 16 12;
  let img = Ctypes.( !@ ) p in
  let c = get_image_color img 11 7 in
  Printf.printf "resized %dx%d, pixel (11,7) = %d %d %d %d\n" (Image.width img) (Image.height img)
    (Color.r c) (Color.g c) (Color.b c) (Color.a c);
  let ck = gen_image_checked 4 4 2 2 Color.black Color.white in
  let c = get_image_color ck 3 1 in
  Printf.printf "checked (3,1) = %d %d %d\n" (Color.r c) (Color.g c) (Color.b c);
  Printf.printf "color_to_int red = %d\n" (color_to_int Color.red);
  let f = fade Color.red 0.5 in
  Printf.printf "fade alpha = %d\n" (Color.a f);
  let h = color_from_hsv 120. 1. 1. in
  Printf.printf "hsv 120 = %d %d %d\n" (Color.r h) (Color.g h) (Color.b h);
  let r1 = Rectangle.create 0. 0. 10. 10. and r2 = Rectangle.create 5. 5. 10. 10. in
  let i = get_collision_rec r1 r2 in
  Printf.printf "collision %b, overlap %.1f %.1f %.1f %.1f\n" (check_collision_recs r1 r2)
    (Rectangle.x i) (Rectangle.y i) (Rectangle.width i) (Rectangle.height i);
  let v = Vector2.add (Vector2.create 1.5 2.) (Vector2.create 0.5 1.) in
  Printf.printf "vector2 %.1f %.1f\n" (Vector2.x v) (Vector2.y v);
  Printf.printf "pixel data size %d\n" (get_pixel_data_size 16 12 PixelFormat.Uncompressed_r8g8b8a8);
  Printf.printf "text %s %d, codepoints %d\n" (text_to_upper "ocaml") (text_length "raylib")
    (get_codepoint_count "héllo");
  unload_image img;
  unload_image ck;
  print_endline "done"
