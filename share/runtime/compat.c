/* libc functions the OCaml runtime/otherlibs reference but emscripten's libc
 * does not provide.  Weak: a real definition (newer emscripten, user code)
 * takes precedence.  They fail with ENOSYS, as unsupported syscalls do. */

#include <errno.h>
#include <signal.h>

__attribute__((weak)) int sigsuspend(const sigset_t *mask)
{
  (void)mask;
  errno = ENOSYS;
  return -1;
}

/* OCaml < 4.12: runtime/afl.c (AFL fuzzing support) attaches shared memory
   when AFL asks for it, which never happens here. */
__attribute__((weak)) void *shmat(int shmid, const void *shmaddr, int shmflg)
{
  (void)shmid; (void)shmaddr; (void)shmflg;
  errno = ENOSYS;
  return (void *)-1;
}

/* OCaml >= 5.5: ocamlc defines these in the C file it links with the runtime
   (prims.c for ocamlrun).  STANDARD mode: the runtime opens argv[0] as the
   bytecode first (see main.c).  The standard library directory is the one
   the runtime of older versions has built in (configure's default prefix). */
__attribute__((weak)) const int caml_byte_program_mode = 0; /* STANDARD */
__attribute__((weak)) const char *caml_runtime_standard_library_default = "/usr/local/lib/ocaml";

/* wasm32: stubs compiled against the headers of an older ocaml-emcc runtime,
   built with ARCH_ALIGN_DOUBLE / ARCH_ALIGN_INT64, read floats and int64s
   through these functions, which the runtime no longer defines.  (A value is
   a pointer-sized integer; the int64 of a custom block follows its ops.) */
#if defined(__wasm32__)
#include <stdint.h>
#include <string.h>

__attribute__((weak)) double caml_Double_val(intptr_t v)
{
  double d;
  memcpy(&d, (void *)v, sizeof d);
  return d;
}

__attribute__((weak)) void caml_Store_double_val(intptr_t v, double d)
{
  memcpy((void *)v, &d, sizeof d);
}

__attribute__((weak)) int64_t caml_Int64_val(intptr_t v)
{
  int64_t i;
  memcpy(&i, (char *)v + sizeof(intptr_t), sizeof i);
  return i;
}
#endif

/* wasm64: emscripten's getaddrinfo (JavaScript) stores ai_canonname with
   BigInt(canon), where canon is null or the JavaScript string of a numeric
   address: BigInt throws on both ("Cannot convert 127.0.0.1 to a BigInt"),
   so every call fails under memory64 (emsdk 6.0.11).  The same function in
   C: numeric addresses, other names through emscripten's DNS emulation
   (_emscripten_lookup_name, as its gethostbyname), each node and its
   ai_addr allocated apart, as its freeaddrinfo frees them. */
#if defined(__wasm64__)
#include <arpa/inet.h>
#include <stdint.h>
#include <string.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/socket.h>

uint32_t _emscripten_lookup_name(const char *name);

static int ocaml_emcc_addrinfo(int family, int type, int proto, const void *addr, int port,
                               struct addrinfo **out)
{
  struct addrinfo *ai = calloc(1, sizeof *ai);
  void *sa = calloc(1, family == AF_INET6 ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in));
  if (ai == NULL || sa == NULL) { free(ai); free(sa); return EAI_MEMORY; }
  if (family == AF_INET6) {
    struct sockaddr_in6 *s = sa;
    s->sin6_family = AF_INET6; s->sin6_port = htons(port);
    memcpy(&s->sin6_addr, addr, sizeof s->sin6_addr);
    ai->ai_addrlen = sizeof *s;
  } else {
    struct sockaddr_in *s = sa;
    s->sin_family = AF_INET; s->sin_port = htons(port);
    memcpy(&s->sin_addr, addr, sizeof s->sin_addr);
    ai->ai_addrlen = sizeof *s;
  }
  ai->ai_family = family; ai->ai_socktype = type; ai->ai_protocol = proto;
  ai->ai_addr = sa;
  *out = ai;
  return 0;
}

__attribute__((weak)) int getaddrinfo(const char *node, const char *service,
                                      const struct addrinfo *hint, struct addrinfo **out)
{
  int flags = 0, family = AF_UNSPEC, type = 0, proto = 0, port = 0;
  struct in_addr a4; struct in6_addr a6;
  if (hint) {
    flags = hint->ai_flags; family = hint->ai_family;
    type = hint->ai_socktype; proto = hint->ai_protocol;
  }
  if (type && !proto) proto = type == SOCK_DGRAM ? IPPROTO_UDP : IPPROTO_TCP;
  if (!type && proto) type = proto == IPPROTO_UDP ? SOCK_DGRAM : SOCK_STREAM;
  if (!proto) proto = IPPROTO_TCP;
  if (!type) type = SOCK_STREAM;
  if (!node && !service) return EAI_NONAME;
  if (flags & ~(AI_PASSIVE | AI_CANONNAME | AI_NUMERICHOST | AI_NUMERICSERV
                | AI_V4MAPPED | AI_ALL | AI_ADDRCONFIG)) return EAI_BADFLAGS;
  if ((flags & AI_CANONNAME) && !node) return EAI_BADFLAGS;
  if (flags & AI_ADDRCONFIG) return EAI_NONAME;
  if (type != SOCK_STREAM && type != SOCK_DGRAM) return EAI_SOCKTYPE;
  if (family != AF_UNSPEC && family != AF_INET && family != AF_INET6) return EAI_FAMILY;
  if (service) {
    char *end;
    port = (int)strtol(service, &end, 10);
    if (end == service) return (flags & AI_NUMERICSERV) ? EAI_NONAME : EAI_SERVICE;
  }
  if (!node) {
    if (family == AF_UNSPEC) family = AF_INET;
    a4.s_addr = (flags & AI_PASSIVE) ? htonl(INADDR_ANY) : htonl(INADDR_LOOPBACK);
    a6 = (flags & AI_PASSIVE) ? in6addr_any : in6addr_loopback;
    return ocaml_emcc_addrinfo(family, type, proto, family == AF_INET6 ? (void *)&a6 : (void *)&a4, port, out);
  }
  if (inet_pton(AF_INET, node, &a4) == 1) {
    if (family == AF_UNSPEC || family == AF_INET)
      return ocaml_emcc_addrinfo(AF_INET, type, proto, &a4, port, out);
    if (family == AF_INET6 && (flags & AI_V4MAPPED)) {
      memset(&a6, 0, sizeof a6); a6.s6_addr[10] = a6.s6_addr[11] = 0xff;
      memcpy(&a6.s6_addr[12], &a4, 4);
      return ocaml_emcc_addrinfo(AF_INET6, type, proto, &a6, port, out);
    }
    return EAI_NONAME;
  }
  if (inet_pton(AF_INET6, node, &a6) == 1) {
    if (family == AF_UNSPEC || family == AF_INET6)
      return ocaml_emcc_addrinfo(AF_INET6, type, proto, &a6, port, out);
    return EAI_NONAME;
  }
  if (flags & AI_NUMERICHOST) return EAI_NONAME;
  {
    uint32_t a = _emscripten_lookup_name(node);
    memcpy(&a4, &a, 4);
  }
  if (family == AF_INET6) {
    memset(&a6, 0, sizeof a6); a6.s6_addr[10] = a6.s6_addr[11] = 0xff;
    memcpy(&a6.s6_addr[12], &a4, 4);
    return ocaml_emcc_addrinfo(AF_INET6, type, proto, &a6, port, out);
  }
  return ocaml_emcc_addrinfo(AF_INET, type, proto, &a4, port, out);
}
#endif
