/* ocaml-emcc: GLFW 3.3 functions that emscripten's GLFW (libglfw.js)
   declares but does not implement.  Weak: a newer emscripten's take
   precedence.  No gamepad is ever present, init hints are ignored. */
#include <GLFW/glfw3.h>

__attribute__((weak)) void glfwInitHint(int hint, int value) { (void)hint; (void)value; }
__attribute__((weak)) int glfwUpdateGamepadMappings(const char *string) { (void)string; return GLFW_FALSE; }
__attribute__((weak)) const char *glfwGetGamepadName(int jid) { (void)jid; return NULL; }
__attribute__((weak)) int glfwGetGamepadState(int jid, GLFWgamepadstate *state) { (void)jid; (void)state; return GLFW_FALSE; }
