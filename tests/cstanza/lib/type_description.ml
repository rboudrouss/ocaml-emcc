open Ctypes

module Types (F : Ctypes.TYPE) = struct
  open F

  type pt

  let pt : pt structure typ = structure "pt"
  let c = field pt "c" char
  let l = field pt "l" long
  let p = field pt "p" (ptr void)
  let d = field pt "d" double
  let () = seal pt
end
