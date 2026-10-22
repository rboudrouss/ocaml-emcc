(* ocaml-lua: the vendored Lua interpreter, OCaml callbacks *)
open Lua_api
let () =
  let ls = LuaL.newstate () in
  LuaL.openlibs ls;
  Lua.pushocamlfunction ls (fun ls ->
    let x = LuaL.checknumber ls 1 in
    Lua.pushnumber ls (x *. 2.); 1);
  Lua.setglobal ls "double";
  let code = {|
    local t = {}
    for i = 1, 10 do t[i] = i * i end
    local s = 0
    for _, v in ipairs(t) do s = s + v end
    result = string.format("sum=%d double=%g upper=%s", s, double(21), string.upper("lua"))
    function fib(n) if n < 2 then return n else return fib(n-1) + fib(n-2) end end
  |} in
  (match LuaL.dostring ls code with true -> () | false -> print_endline "dostring failed");
  Lua.getglobal ls "result";
  print_endline (Option.get (Lua.tostring ls (-1)));
  Lua.pop ls 1;
  Lua.getglobal ls "fib"; Lua.pushinteger ls 20;
  (match Lua.pcall ls 1 1 0 with Lua.LUA_OK -> Printf.printf "fib 20 = %g\n" (Lua.tonumber ls (-1)) | _ -> print_endline "pcall failed");
  Lua.pop ls 1;
  (match LuaL.dostring ls "error('boom')" with
   | true -> print_endline "no error?!"
   | false -> Printf.printf "error: %s\n" (Option.value (Lua.tostring ls (-1)) ~default:"?"));
  Lua.settop ls 0;
  (match LuaL.dostring ls "return math.floor(math.sqrt(2) * 1e6), os.time() > 0, #string.rep('ab', 1000)" with
   | true -> Printf.printf "math %g, time %b, rep %g\n" (Lua.tonumber ls 1) (Lua.toboolean ls 2) (Lua.tonumber ls 3)
   | false -> print_endline "failed");
  print_endline "done"
