(* Unix.map_file: shared writable mappings of a file, written back to it
   (emscripten's and WASI's mappings are copies, written back when they are
   unmapped, by the finalizer of their bigarray: the file is read once they
   were collected), a longer mapping growing the file, a read-only one *)
let read f = In_channel.with_open_bin f In_channel.input_all

let map ?(shared = true) fd n = Bigarray.array1_of_genarray (Unix.map_file fd Bigarray.char Bigarray.c_layout shared [| n |])

let[@inline never] change fd =
  let a = map fd (-1) in
  Printf.printf "mapped %d bytes: %c%c\n" (Bigarray.Array1.dim a) a.{0} a.{7};
  a.{0} <- 'H';
  a.{7} <- 'W'

let[@inline never] grow fd =
  let a = map fd 16 in
  Printf.printf "grown to %d bytes\n" (Unix.fstat fd).Unix.st_size;
  String.iteri (fun i c -> a.{12 + i} <- c) "!!!!"

(* (and their bigarrays are no longer referenced by anything) *)
let[@inline never] collect () =
  for _ = 1 to 3 do
    ignore (Sys.opaque_identity (Bigarray.Array1.create Bigarray.char Bigarray.c_layout 1));
    Gc.full_major ()
  done

let () =
  let f = "mapped.bin" in
  Out_channel.with_open_bin f (fun oc -> output_string oc "hello, world");
  let fd = Unix.openfile f [ Unix.O_RDWR ] 0 in
  change fd;
  collect ();
  grow fd;
  collect ();
  Unix.close fd;
  collect ();
  Printf.printf "written back: %s\n" (read f);
  let fd = Unix.openfile f [ Unix.O_RDONLY ] 0 in
  let a = map ~shared:false fd (-1) in
  Printf.printf "read-only: %c%c%c\n" a.{0} a.{7} a.{15};
  Unix.close fd;
  Sys.remove f
