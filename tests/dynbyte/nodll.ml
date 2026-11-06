external answer : unit -> int = "cst_answer"
let () = App.register (fun _ -> "nodll:" ^ string_of_int (answer ()))
