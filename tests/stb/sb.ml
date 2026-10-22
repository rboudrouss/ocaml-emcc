(* stb_image: decode images written here (PGM/PPM, BMP) *)
let write f s = let oc = open_out_bin f in output_string oc s; close_out oc
let () =
  let w, h = 7, 5 in
  let px = String.init (w * h * 3) (fun i -> Char.chr ((i * 37) land 255)) in
  write "img.ppm" (Printf.sprintf "P6\n%d %d\n255\n%s" w h px);
  (match Stb_image.load "img.ppm" with
   | Ok img ->
       let d = Stb_image.data img in
       let sum = ref 0 in
       for i = 0 to Bigarray.Array1.dim d - 1 do sum := !sum + d.{i} done;
       Printf.printf "ppm: %dx%d channels %d sum %d\n" (Stb_image.width img) (Stb_image.height img) (Stb_image.channels img) !sum
   | Error (`Msg m) -> Printf.printf "ppm error: %s\n" m);
  (match Stb_image.load ~channels:1 "img.ppm" with
   | Ok img -> Printf.printf "ppm as grey: channels %d first %d\n" (Stb_image.channels img) (Stb_image.data img).{0}
   | Error (`Msg m) -> Printf.printf "error: %s\n" m);
  (match Stb_image.loadf "img.ppm" with
   | Ok img -> Printf.printf "float: %.4f\n" (Stb_image.data img).{5}
   | Error (`Msg m) -> Printf.printf "error: %s\n" m);
  (match Stb_image.load "nope.png" with Ok _ -> () | Error (`Msg m) -> Printf.printf "missing: %s\n" m);
  Sys.remove "img.ppm";
  print_endline "done"
