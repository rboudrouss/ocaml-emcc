external answer : unit -> int = "cst_answer"
external show : int -> string = "cst_show"
let () = App.register (fun _ -> "cst:" ^ string_of_int (answer ()) ^ show 7)
