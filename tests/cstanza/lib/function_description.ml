open Ctypes
module Types = Types_generated

module Functions (F : Ctypes.FOREIGN) = struct
  open F

  let pt_sum = foreign "pt_sum" (ptr Types.pt @-> returning long)
  let pt_fill = foreign "pt_fill" (ptr Types.pt @-> returning void)
  let pt_size = foreign "pt_size" (void @-> returning size_t)
end
