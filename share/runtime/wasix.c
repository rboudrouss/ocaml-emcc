/* Sockets for a WASI module on wasmer (`ocaml-emcc link --wasix`): WASIX.
 *
 * WASI preview1 has no call creating a socket (only accept on one the host
 * preopens, wasi.c); WASIX, wasmer's extension of preview1 (imports
 * `wasix_32v1.*`), has BSD sockets: open, bind, connect, listen, accept,
 * options, addresses, name resolution.  These definitions replace the
 * failing ones of wasi.c (weak) with WASIX calls, the conversions of
 * wasix-libc (cloudlibc/src/libc/sys/socket).  Reading, writing, polling
 * and closing a socket are WASI's fd calls, as for files.  A host without
 * WASIX (wasmtime, node:wasi) refuses the module: its imports are missing. */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <wasi/api.h>
#include <emscripten/syscalls.h>

#define WASIX(name) __attribute__((import_module("wasix_32v1"), import_name(#name)))

/* wasix_v1.witx's types */
enum { AF_WX_UNSPEC = 0, AF_WX_INET4 = 1, AF_WX_INET6 = 2, AF_WX_UNIX = 3 };
enum { SOCK_WX_STREAM = 1, SOCK_WX_DGRAM = 2, SOCK_WX_RAW = 3, SOCK_WX_SEQPACKET = 4 };
enum {
  OPT_REUSE_PORT = 1, OPT_REUSE_ADDR = 2, OPT_NO_DELAY = 3, OPT_DONT_ROUTE = 4, OPT_ONLY_V6 = 5, OPT_BROADCAST = 6,
  OPT_MULTICAST_LOOP_V4 = 7, OPT_MULTICAST_LOOP_V6 = 8, OPT_LISTENING = 10, OPT_LAST_ERROR = 11,
  OPT_KEEP_ALIVE = 12, OPT_LINGER = 13, OPT_OOB_INLINE = 14, OPT_RECV_BUF_SIZE = 15, OPT_SEND_BUF_SIZE = 16,
  OPT_RECV_TIMEOUT = 19, OPT_SEND_TIMEOUT = 20, OPT_TTL = 23, OPT_MULTICAST_TTL_V4 = 24, OPT_TYPE = 25, OPT_PROTO = 26
};

/* an address and its port (addr_port): the port in host order, the
   address in network order */
typedef struct {
  uint8_t tag;
  union {
    struct { uint16_t port; uint8_t addr[4]; } inet4;
    struct { uint16_t port; uint8_t addr[16]; uint16_t flow_info1, flow_info0, scope_id1, scope_id0; } inet6;
    uint8_t unix_path[108];
  } u;
} wx_addr_port;
_Static_assert(sizeof(wx_addr_port) == 110, "addr_port");

/* an address (addr_ip, resolve's) */
typedef struct {
  uint8_t tag;
  union { uint8_t inet4[4]; uint8_t inet6[16]; uint16_t align; } u;
} wx_addr_ip;
_Static_assert(sizeof(wx_addr_ip) == 18, "addr_ip");

typedef struct {
  uint8_t tag; /* 1: some */
  uint64_t some;
} wx_option_timestamp;
_Static_assert(sizeof(wx_option_timestamp) == 16, "option_timestamp");

int32_t wx_sock_open(int32_t af, int32_t type, int32_t proto, int32_t *fd) WASIX(sock_open);
int32_t wx_sock_pair(int32_t af, int32_t type, int32_t proto, int32_t *fd1, int32_t *fd2) WASIX(sock_pair);
int32_t wx_sock_bind(int32_t fd, const wx_addr_port *addr) WASIX(sock_bind);
int32_t wx_sock_listen(int32_t fd, int32_t backlog) WASIX(sock_listen);
int32_t wx_sock_accept_v2(int32_t fd, int32_t flags, int32_t *nfd, wx_addr_port *addr) WASIX(sock_accept_v2);
int32_t wx_sock_connect(int32_t fd, const wx_addr_port *addr) WASIX(sock_connect);
int32_t wx_sock_recv_from(int32_t fd, const __wasi_iovec_t *iov, int32_t n, int32_t riflags, uint32_t *nread,
                          uint16_t *roflags, wx_addr_port *addr) WASIX(sock_recv_from);
int32_t wx_sock_send_to(int32_t fd, const __wasi_ciovec_t *iov, int32_t n, int32_t siflags, const wx_addr_port *addr,
                        uint32_t *nsent) WASIX(sock_send_to);
int32_t wx_sock_addr_local(int32_t fd, wx_addr_port *addr) WASIX(sock_addr_local);
int32_t wx_sock_addr_peer(int32_t fd, wx_addr_port *addr) WASIX(sock_addr_peer);
int32_t wx_sock_set_opt_flag(int32_t fd, int32_t opt, int32_t flag) WASIX(sock_set_opt_flag);
int32_t wx_sock_get_opt_flag(int32_t fd, int32_t opt, uint8_t *flag) WASIX(sock_get_opt_flag);
int32_t wx_sock_set_opt_size(int32_t fd, int32_t opt, int64_t size) WASIX(sock_set_opt_size);
int32_t wx_sock_get_opt_size(int32_t fd, int32_t opt, uint64_t *size) WASIX(sock_get_opt_size);
int32_t wx_sock_set_opt_time(int32_t fd, int32_t opt, const wx_option_timestamp *t) WASIX(sock_set_opt_time);
int32_t wx_sock_get_opt_time(int32_t fd, int32_t opt, wx_option_timestamp *t) WASIX(sock_get_opt_time);
int32_t wx_resolve(const char *host, int32_t len, int32_t port, wx_addr_ip *addrs, int32_t n, uint32_t *found)
    WASIX(resolve);
int32_t wx_sock_shutdown(int32_t fd, int32_t how)
    __attribute__((import_module("wasi_snapshot_preview1"), import_name("sock_shutdown")));

int32_t wx_fd_dup(int32_t fd, int32_t *nfd) WASIX(fd_dup);

/* dup (wasi.c) */
int ocaml_emcc_fd_dup(int fd)
{
  int32_t d;
  int e = wx_fd_dup(fd, &d);
  return e ? -e : d;
}

/* -------------------------------------------------------------- addresses */

static int to_wasix(const struct sockaddr *sa, socklen_t len, wx_addr_port *a)
{
  memset(a, 0, sizeof *a);
  if (!sa || len < sizeof(sa_family_t)) return -EINVAL;
  switch (sa->sa_family) {
  case AF_INET: {
    const struct sockaddr_in *in = (const struct sockaddr_in *)sa;
    if (len < sizeof *in) return -EINVAL;
    a->tag = AF_WX_INET4;
    a->u.inet4.port = ntohs(in->sin_port);
    memcpy(a->u.inet4.addr, &in->sin_addr, 4);
    return 0;
  }
  case AF_INET6: {
    const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)sa;
    if (len < sizeof *in6) return -EINVAL;
    a->tag = AF_WX_INET6;
    a->u.inet6.port = ntohs(in6->sin6_port);
    memcpy(a->u.inet6.addr, &in6->sin6_addr, 16);
    a->u.inet6.flow_info1 = in6->sin6_flowinfo >> 16;
    a->u.inet6.flow_info0 = in6->sin6_flowinfo & 0xffff;
    a->u.inet6.scope_id1 = in6->sin6_scope_id >> 16;
    a->u.inet6.scope_id0 = in6->sin6_scope_id & 0xffff;
    return 0;
  }
  case AF_UNIX: {
    size_t n = len - offsetof(struct sockaddr_un, sun_path);
    if (len <= offsetof(struct sockaddr_un, sun_path) || n >= sizeof a->u.unix_path) return -EINVAL;
    a->tag = AF_WX_UNIX;
    memcpy(a->u.unix_path, ((const struct sockaddr_un *)sa)->sun_path, n);
    return 0;
  }
  default:
    return -EAFNOSUPPORT;
  }
}

/* wasmer reads the ports in host order, but writes them in network order
   (7.5): bind a socket to a port and read it back, once (assuming
   wasmer's when no port is free) */
static uint16_t port_out(uint16_t port)
{
  static int swapped = -1;
  if (swapped < 0) {
    swapped = 1;
    int32_t fd;
    if (wx_sock_open(AF_WX_INET4, SOCK_WX_DGRAM, IPPROTO_UDP, &fd) == 0) {
      for (uint16_t p = 49231; p < 49231 + 64; p += 7) {
        wx_addr_port a = { .tag = AF_WX_INET4, .u.inet4 = { p, { 127, 0, 0, 1 } } };
        if (wx_sock_bind(fd, &a)) continue;
        if (wx_sock_addr_local(fd, &a) == 0) swapped = a.u.inet4.port != p;
        break;
      }
      (void)__wasi_fd_close(fd);
    }
  }
  return swapped ? ntohs(port) : port;
}

/* (len: the size of sa, then of the address, as the kernel's) */
static void of_wasix(const wx_addr_port *a, struct sockaddr *sa, socklen_t *len)
{
  if (!sa || !len) return;
  struct sockaddr_storage ss;
  socklen_t n;
  memset(&ss, 0, sizeof ss);
  switch (a->tag) {
  case AF_WX_INET4: {
    struct sockaddr_in *in = (struct sockaddr_in *)&ss;
    in->sin_family = AF_INET;
    in->sin_port = htons(port_out(a->u.inet4.port));
    memcpy(&in->sin_addr, a->u.inet4.addr, 4);
    n = sizeof *in;
    break;
  }
  case AF_WX_INET6: {
    struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)&ss;
    in6->sin6_family = AF_INET6;
    in6->sin6_port = htons(port_out(a->u.inet6.port));
    memcpy(&in6->sin6_addr, a->u.inet6.addr, 16);
    in6->sin6_flowinfo = (uint32_t)a->u.inet6.flow_info1 << 16 | a->u.inet6.flow_info0;
    in6->sin6_scope_id = (uint32_t)a->u.inet6.scope_id1 << 16 | a->u.inet6.scope_id0;
    n = sizeof *in6;
    break;
  }
  case AF_WX_UNIX: {
    struct sockaddr_un *un = (struct sockaddr_un *)&ss;
    un->sun_family = AF_UNIX;
    memcpy(un->sun_path, a->u.unix_path, sizeof un->sun_path - 1);
    n = offsetof(struct sockaddr_un, sun_path) + strlen(un->sun_path) + 1;
    break;
  }
  default:
    ss.ss_family = AF_UNSPEC;
    n = sizeof(sa_family_t);
  }
  memcpy(sa, &ss, *len < n ? *len : n);
  *len = n;
}

/* ---------------------------------------------------------------- sockets */

static int set_fdflags(int fd, int nonblock)
{
  __wasi_fdstat_t s;
  __wasi_errno_t e = __wasi_fd_fdstat_get(fd, &s);
  if (!e) e = __wasi_fd_fdstat_set_flags(fd, nonblock ? s.fs_flags | __WASI_FDFLAGS_NONBLOCK : s.fs_flags);
  return -e;
}

int __syscall_socket(int domain, int type, int protocol, int u1, int u2, int u3)
{
  (void)u1; (void)u2; (void)u3;
  int af, st;
  switch (domain) {
  case AF_INET: af = AF_WX_INET4; break;
  case AF_INET6: af = AF_WX_INET6; break;
  case AF_UNIX: af = AF_WX_UNIX; break;
  default: return -EAFNOSUPPORT;
  }
  switch (type & ~(SOCK_NONBLOCK | SOCK_CLOEXEC)) {
  case SOCK_STREAM: st = SOCK_WX_STREAM; break;
  case SOCK_DGRAM: st = SOCK_WX_DGRAM; break;
  case SOCK_RAW: st = SOCK_WX_RAW; break;
  case SOCK_SEQPACKET: st = SOCK_WX_SEQPACKET; break;
  default: return -EINVAL;
  }
  if (!protocol && af != AF_WX_UNIX) protocol = st == SOCK_WX_STREAM ? IPPROTO_TCP : st == SOCK_WX_DGRAM ? IPPROTO_UDP : 0;
  int32_t fd;
  int e = wx_sock_open(af, st, protocol, &fd);
  if (e) return -e;
  if (type & SOCK_NONBLOCK && (e = set_fdflags(fd, 1))) {
    close(fd);
    return e;
  }
  return fd;
}

int __syscall_socketpair(int domain, int type, int protocol, int fd[2], int u1, int u2)
{
  (void)u1; (void)u2;
  if (domain != AF_UNIX) return -EAFNOSUPPORT;
  int st = (type & ~(SOCK_NONBLOCK | SOCK_CLOEXEC)) == SOCK_DGRAM ? SOCK_WX_DGRAM : SOCK_WX_STREAM;
  int32_t a, b;
  int e = wx_sock_pair(AF_WX_UNIX, st, protocol, &a, &b);
  if (e) return -e;
  if (type & SOCK_NONBLOCK && ((e = set_fdflags(a, 1)) || (e = set_fdflags(b, 1)))) {
    close(a);
    close(b);
    return e;
  }
  fd[0] = a;
  fd[1] = b;
  return 0;
}

int __syscall_bind(int s, const struct sockaddr *sa, socklen_t len, int u1, int u2, int u3)
{
  (void)u1; (void)u2; (void)u3;
  wx_addr_port a;
  int e = to_wasix(sa, len, &a);
  return e ? e : -wx_sock_bind(s, &a);
}

/* Always blocking: wasmer's (7.5) non-blocking connect never completes,
   and its blocking one succeeds when refused, the error left in SO_ERROR
   (a non-blocking socket connected at once, as connect may) */
int __syscall_connect(int s, const struct sockaddr *sa, socklen_t len, int u1, int u2, int u3)
{
  (void)u1; (void)u2; (void)u3;
  wx_addr_port a;
  int e = to_wasix(sa, len, &a);
  if (e) return e;
  __wasi_fdstat_t st;
  int nonblock = __wasi_fd_fdstat_get(s, &st) == 0 && st.fs_flags & __WASI_FDFLAGS_NONBLOCK;
  if (nonblock) (void)__wasi_fd_fdstat_set_flags(s, st.fs_flags & ~__WASI_FDFLAGS_NONBLOCK);
  e = wx_sock_connect(s, &a);
  uint64_t last;
  if (!e && wx_sock_get_opt_size(s, OPT_LAST_ERROR, &last) == 0) e = (int)last;
  if (nonblock) (void)__wasi_fd_fdstat_set_flags(s, st.fs_flags);
  return -e;
}

int __syscall_listen(int s, int backlog, int u1, int u2, int u3, int u4)
{
  (void)u1; (void)u2; (void)u3; (void)u4;
  return -wx_sock_listen(s, backlog);
}

int __syscall_accept4(int s, struct sockaddr *sa, socklen_t *len, int flags, int u1, int u2)
{
  (void)u1; (void)u2;
  if (flags & ~(SOCK_NONBLOCK | SOCK_CLOEXEC)) return -EINVAL;
  int32_t fd;
  wx_addr_port a;
  int e = wx_sock_accept_v2(s, flags & SOCK_NONBLOCK ? __WASI_FDFLAGS_NONBLOCK : 0, &fd, &a);
  if (e) return -e;
  of_wasix(&a, sa, len);
  return fd;
}

int __syscall_getsockname(int s, struct sockaddr *sa, socklen_t *len, int u1, int u2, int u3)
{
  (void)u1; (void)u2; (void)u3;
  wx_addr_port a;
  int e = wx_sock_addr_local(s, &a);
  if (e) return -e;
  of_wasix(&a, sa, len);
  return 0;
}

int __syscall_getpeername(int s, struct sockaddr *sa, socklen_t *len, int u1, int u2, int u3)
{
  (void)u1; (void)u2; (void)u3;
  wx_addr_port a;
  int e = wx_sock_addr_peer(s, &a);
  if (e) return -e;
  /* (wasmer: the unspecified address when not connected) */
  static const uint8_t zero[16];
  if ((a.tag == AF_WX_INET4 && !a.u.inet4.port && !memcmp(a.u.inet4.addr, zero, 4))
      || (a.tag == AF_WX_INET6 && !a.u.inet6.port && !memcmp(a.u.inet6.addr, zero, 16)))
    return -ENOTCONN;
  of_wasix(&a, sa, len);
  return 0;
}

static int riflags(int flags)
{
  return (flags & MSG_PEEK ? __WASI_RIFLAGS_RECV_PEEK : 0) | (flags & MSG_WAITALL ? __WASI_RIFLAGS_RECV_WAITALL : 0)
         | (flags & MSG_DONTWAIT ? 8 /* RECV_DONT_WAIT */ : 0);
}

/* (with no address asked, preview1's sock_recv: wasmer's sock_recv_from
   is for datagrams, ENOTSUP on a stream) */
static int recv_iov(int s, const struct iovec *iov, int n, int flags, struct sockaddr *sa, socklen_t *len)
{
  uint32_t nread;
  uint16_t ro;
  wx_addr_port a;
  memset(&a, 0, sizeof a);
  int e = __WASI_ERRNO_NOTSUP;
  if (sa && len) e = wx_sock_recv_from(s, (const __wasi_iovec_t *)iov, n, riflags(flags), &nread, &ro, &a);
  if (!e) {
    of_wasix(&a, sa, len);
    return nread;
  }
  if (e != __WASI_ERRNO_NOTSUP) return -e;
  __wasi_size_t k;
  if ((e = __wasi_sock_recv(s, (const __wasi_iovec_t *)iov, n, riflags(flags), &k, &ro))) return -e;
  if (sa && len) *len = 0;
  return k;
}

/* (sending: MSG_NOSIGNAL is moot, no signals; MSG_DONTWAIT unsupported) */
static int send_iov(int s, const struct iovec *iov, int n, const struct sockaddr *sa, socklen_t len)
{
  uint32_t nsent;
  if (!sa) {
    __wasi_size_t k;
    int e = __wasi_fd_write(s, (const __wasi_ciovec_t *)iov, n, &k);
    return e ? -e : (int)k;
  }
  wx_addr_port a;
  int e = to_wasix(sa, len, &a);
  if (e) return e;
  e = wx_sock_send_to(s, (const __wasi_ciovec_t *)iov, n, 0, &a, &nsent);
  if (e == __WASI_ERRNO_NOTSUP) return send_iov(s, iov, n, NULL, 0); /* (a stream: connected) */
  return e ? -e : (int)nsent;
}

int __syscall_recvfrom(int s, void *buf, size_t n, int flags, struct sockaddr *sa, socklen_t *len)
{
  struct iovec iov = { buf, n };
  return recv_iov(s, &iov, 1, flags, sa, len);
}

int __syscall_sendto(int s, const void *buf, size_t n, int flags, const struct sockaddr *sa, socklen_t len)
{
  (void)flags;
  struct iovec iov = { (void *)buf, n };
  return send_iov(s, &iov, 1, sa, len);
}

int __syscall_recvmsg(int s, struct msghdr *m, int flags, int u1, int u2, int u3)
{
  (void)u1; (void)u2; (void)u3;
  socklen_t len = m->msg_namelen;
  int r = recv_iov(s, m->msg_iov, m->msg_iovlen, flags, m->msg_name, m->msg_name ? &len : NULL);
  if (r >= 0) {
    if (m->msg_name) m->msg_namelen = len;
    m->msg_controllen = 0;
    m->msg_flags = 0;
  }
  return r;
}

int __syscall_sendmsg(int s, const struct msghdr *m, int flags, int u1, int u2, int u3)
{
  (void)flags; (void)u1; (void)u2; (void)u3;
  if (m->msg_controllen) return -EOPNOTSUPP; /* no descriptors passed */
  return send_iov(s, m->msg_iov, m->msg_iovlen, m->msg_name, m->msg_namelen);
}

int __syscall_shutdown(int s, int how, int u1, int u2, int u3, int u4)
{
  (void)u1; (void)u2; (void)u3; (void)u4;
  int f = how == SHUT_RD ? __WASI_SDFLAGS_RD : how == SHUT_WR ? __WASI_SDFLAGS_WR : __WASI_SDFLAGS_RD | __WASI_SDFLAGS_WR;
  return -wx_sock_shutdown(s, f);
}

/* ---------------------------------------------------------------- options */

enum kind { FLAG, SIZE, TIME, LINGER, TYPE, ERROR };

static int option(int level, int name, enum kind *k)
{
  if (level == IPPROTO_TCP && name == TCP_NODELAY) return *k = FLAG, OPT_NO_DELAY;
  if (level == IPPROTO_IPV6 && name == IPV6_V6ONLY) return *k = FLAG, OPT_ONLY_V6;
  if (level == IPPROTO_IP && name == IP_TTL) return *k = SIZE, OPT_TTL;
  if (level == IPPROTO_IP && name == IP_MULTICAST_TTL) return *k = SIZE, OPT_MULTICAST_TTL_V4;
  if (level == IPPROTO_IP && name == IP_MULTICAST_LOOP) return *k = FLAG, OPT_MULTICAST_LOOP_V4;
  if (level == IPPROTO_IPV6 && name == IPV6_MULTICAST_LOOP) return *k = FLAG, OPT_MULTICAST_LOOP_V6;
  if (level != SOL_SOCKET) return -1;
  switch (name) {
  case SO_REUSEADDR: return *k = FLAG, OPT_REUSE_ADDR;
  case SO_REUSEPORT: return *k = FLAG, OPT_REUSE_PORT;
  case SO_DONTROUTE: return *k = FLAG, OPT_DONT_ROUTE;
  case SO_BROADCAST: return *k = FLAG, OPT_BROADCAST;
  case SO_KEEPALIVE: return *k = FLAG, OPT_KEEP_ALIVE;
  case SO_OOBINLINE: return *k = FLAG, OPT_OOB_INLINE;
  case SO_ACCEPTCONN: return *k = FLAG, OPT_LISTENING;
  case SO_SNDBUF: return *k = SIZE, OPT_SEND_BUF_SIZE;
  case SO_RCVBUF: return *k = SIZE, OPT_RECV_BUF_SIZE;
  case SO_RCVTIMEO: return *k = TIME, OPT_RECV_TIMEOUT;
  case SO_SNDTIMEO: return *k = TIME, OPT_SEND_TIMEOUT;
  case SO_LINGER: return *k = LINGER, OPT_LINGER;
  case SO_TYPE: return *k = TYPE, OPT_TYPE;
  case SO_ERROR: return *k = ERROR, OPT_LAST_ERROR;
  default: return -1;
  }
}

static int int_value(const void *v, socklen_t len)
{
  int x = 0;
  memcpy(&x, v, len < sizeof x ? len : sizeof x);
  return x;
}

static void put(void *v, socklen_t *len, const void *x, socklen_t n)
{
  memcpy(v, x, *len < n ? *len : n);
  *len = n;
}

int __syscall_setsockopt(int s, int level, int name, const void *v, socklen_t len, int u)
{
  (void)u;
  enum kind k;
  int opt = option(level, name, &k);
  if (opt < 0) return -ENOPROTOOPT;
  wx_option_timestamp t = { 0, 0 };
  switch (k) {
  case FLAG: return -wx_sock_set_opt_flag(s, opt, int_value(v, len) != 0);
  case SIZE: return -wx_sock_set_opt_size(s, opt, int_value(v, len));
  case TIME: {
    if (len < sizeof(struct timeval)) return -EINVAL;
    const struct timeval *tv = v;
    if (tv->tv_sec || tv->tv_usec) t.tag = 1, t.some = (uint64_t)tv->tv_sec * 1000000000 + (uint64_t)tv->tv_usec * 1000;
    return -wx_sock_set_opt_time(s, opt, &t);
  }
  case LINGER: {
    if (len < sizeof(struct linger)) return -EINVAL;
    const struct linger *l = v;
    if (l->l_onoff) t.tag = 1, t.some = (uint64_t)l->l_linger * 1000000000;
    return -wx_sock_set_opt_time(s, opt, &t);
  }
  default: return -ENOPROTOOPT; /* SO_TYPE, SO_ERROR: read-only */
  }
}

int __syscall_getsockopt(int s, int level, int name, void *v, socklen_t *len, int u)
{
  (void)u;
  enum kind k;
  int opt = option(level, name, &k);
  if (opt < 0) return -ENOPROTOOPT;
  int e, x;
  switch (k) {
  case FLAG: {
    uint8_t f;
    if ((e = wx_sock_get_opt_flag(s, opt, &f))) return -e;
    x = f;
    break;
  }
  case SIZE: case ERROR: {
    uint64_t n;
    e = wx_sock_get_opt_size(s, opt, &n);
    if (e && k == ERROR) n = 0; /* (no error recorded) */
    else if (e) return -e;
    x = (int)n;
    break;
  }
  case TIME: case LINGER: {
    wx_option_timestamp t;
    if ((e = wx_sock_get_opt_time(s, opt, &t))) return -e;
    uint64_t ns = t.tag == 1 ? t.some : 0;
    if (k == LINGER) {
      struct linger l = { t.tag == 1, (int)(ns / 1000000000) };
      put(v, len, &l, sizeof l);
    } else {
      struct timeval tv = { (time_t)(ns / 1000000000), (suseconds_t)(ns % 1000000000 / 1000) };
      put(v, len, &tv, sizeof tv);
    }
    return 0;
  }
  case TYPE: {
    __wasi_fdstat_t st;
    if ((e = __wasi_fd_fdstat_get(s, &st))) return -e;
    if (st.fs_filetype == __WASI_FILETYPE_SOCKET_STREAM) x = SOCK_STREAM;
    else if (st.fs_filetype == __WASI_FILETYPE_SOCKET_DGRAM) x = SOCK_DGRAM;
    else return -ENOTSOCK;
    break;
  }
  }
  put(v, len, &x, sizeof x);
  return 0;
}

/* --------------------------------------------------------- name resolution */

#define MAX_ADDRS 16

/* the addresses of a host name (or numeric address) of a family: their
   number, or an EAI_ error (negative) */
static int resolve(const char *host, int family, wx_addr_ip *out)
{
  struct in_addr a4;
  struct in6_addr a6;
  if (inet_pton(AF_INET, host, &a4) == 1) {
    if (family == AF_INET6) return EAI_ADDRFAMILY;
    out[0].tag = AF_WX_INET4;
    memcpy(out[0].u.inet4, &a4, 4);
    return 1;
  }
  if (inet_pton(AF_INET6, host, &a6) == 1) {
    if (family == AF_INET) return EAI_ADDRFAMILY;
    out[0].tag = AF_WX_INET6;
    memcpy(out[0].u.inet6, &a6, 16);
    return 1;
  }
  uint32_t found = 0;
  if (wx_resolve(host, strlen(host), 0, out, MAX_ADDRS, &found) || found == 0) return EAI_NONAME;
  int n = 0;
  for (uint32_t i = 0; i < found && i < MAX_ADDRS; i++) {
    int f = out[i].tag == AF_WX_INET4 ? AF_INET : out[i].tag == AF_WX_INET6 ? AF_INET6 : -1;
    if (f < 0 || (family != AF_UNSPEC && f != family)) continue;
    out[n++] = out[i];
  }
  return n ? n : EAI_NONAME;
}

static int service_port(const char *serv, int socktype, int flags, int *port)
{
  *port = 0;
  if (!serv) return 0;
  char *end;
  long p = strtol(serv, &end, 10);
  if (*serv && !*end && p >= 0 && p < 65536) {
    *port = p;
    return 0;
  }
  if (flags & AI_NUMERICSERV) return EAI_NONAME;
  struct servent *s = getservbyname(serv, socktype == SOCK_DGRAM ? "udp" : "tcp");
  if (!s) return EAI_SERVICE;
  *port = ntohs(s->s_port);
  return 0;
}

int getaddrinfo(const char *host, const char *serv, const struct addrinfo *hints, struct addrinfo **res)
{
  int family = hints ? hints->ai_family : AF_UNSPEC;
  int socktype = hints ? hints->ai_socktype : 0;
  int protocol = hints ? hints->ai_protocol : 0;
  int flags = hints ? hints->ai_flags : 0;
  if (!host && !serv) return EAI_NONAME;
  if (family != AF_UNSPEC && family != AF_INET && family != AF_INET6) return EAI_FAMILY;
  int port, e = service_port(serv, socktype, flags, &port);
  if (e) return e;
  wx_addr_ip addrs[MAX_ADDRS];
  int n;
  memset(addrs, 0, sizeof addrs);
  if (host) {
    if (flags & AI_NUMERICHOST) {
      struct in6_addr tmp;
      if (inet_pton(AF_INET, host, &tmp) != 1 && inet_pton(AF_INET6, host, &tmp) != 1) return EAI_NONAME;
    }
    if ((n = resolve(host, family, addrs)) < 0) return n;
  } else {
    /* the wildcard or loopback addresses */
    int passive = flags & AI_PASSIVE;
    n = 0;
    if (family != AF_INET) {
      addrs[n].tag = AF_WX_INET6;
      if (!passive) addrs[n].u.inet6[15] = 1;
      n++;
    }
    if (family != AF_INET6) {
      addrs[n].tag = AF_WX_INET4;
      if (!passive) memcpy(addrs[n].u.inet4, "\177\0\0\1", 4);
      n++;
    }
  }
  /* each address with each socket type asked (both if none) */
  static const int types[] = { SOCK_STREAM, SOCK_DGRAM };
  struct addrinfo *first = NULL, **next = &first;
  for (int i = 0; i < n; i++)
    for (int t = 0; t < 2; t++) {
      if (socktype && socktype != types[t]) continue;
      struct { struct addrinfo ai; struct sockaddr_storage sa; char canon[256]; } *r = calloc(1, sizeof *r);
      if (!r) {
        freeaddrinfo(first);
        return EAI_MEMORY;
      }
      r->ai.ai_socktype = types[t];
      r->ai.ai_protocol = protocol ? protocol : types[t] == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP;
      r->ai.ai_addr = (struct sockaddr *)&r->sa;
      if (addrs[i].tag == AF_WX_INET4) {
        struct sockaddr_in *in = (struct sockaddr_in *)&r->sa;
        in->sin_family = AF_INET;
        in->sin_port = htons(port);
        memcpy(&in->sin_addr, addrs[i].u.inet4, 4);
        r->ai.ai_family = AF_INET;
        r->ai.ai_addrlen = sizeof *in;
      } else {
        struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)&r->sa;
        in6->sin6_family = AF_INET6;
        in6->sin6_port = htons(port);
        memcpy(&in6->sin6_addr, addrs[i].u.inet6, 16);
        r->ai.ai_family = AF_INET6;
        r->ai.ai_addrlen = sizeof *in6;
      }
      if (first == NULL && host && flags & AI_CANONNAME) {
        strncpy(r->canon, host, sizeof r->canon - 1);
        r->ai.ai_canonname = r->canon;
      }
      *next = &r->ai;
      next = &r->ai.ai_next;
    }
  *res = first;
  return first ? 0 : EAI_SOCKTYPE;
}

/* (one block per entry: musl's freeaddrinfo frees a list of its own) */
void freeaddrinfo(struct addrinfo *ai)
{
  while (ai) {
    struct addrinfo *next = ai->ai_next;
    free(ai);
    ai = next;
  }
}

/* numeric only: WASIX has no reverse lookup */
int getnameinfo(const struct sockaddr *sa, socklen_t salen, char *host, socklen_t hostlen, char *serv,
                socklen_t servlen, int flags)
{
  const void *addr;
  int port;
  if (sa->sa_family == AF_INET && salen >= sizeof(struct sockaddr_in)) {
    addr = &((const struct sockaddr_in *)sa)->sin_addr;
    port = ntohs(((const struct sockaddr_in *)sa)->sin_port);
  } else if (sa->sa_family == AF_INET6 && salen >= sizeof(struct sockaddr_in6)) {
    addr = &((const struct sockaddr_in6 *)sa)->sin6_addr;
    port = ntohs(((const struct sockaddr_in6 *)sa)->sin6_port);
  } else
    return EAI_FAMILY;
  if (host && hostlen) {
    if (flags & NI_NAMEREQD) return EAI_NONAME;
    if (!inet_ntop(sa->sa_family, addr, host, hostlen)) return EAI_OVERFLOW;
  }
  if (serv && servlen) {
    struct servent *s = flags & NI_NUMERICSERV ? NULL : getservbyport(htons(port), flags & NI_DGRAM ? "udp" : "tcp");
    int k = s ? snprintf(serv, servlen, "%s", s->s_name) : snprintf(serv, servlen, "%d", port);
    if (k < 0 || (socklen_t)k >= servlen) return EAI_OVERFLOW;
  }
  return 0;
}

/* gethostbyname: musl's lookup, which emscripten's replaces with its
   JavaScript's (_emscripten_lookup_name, which cannot fail) */
struct address {
  int family;
  unsigned scopeid;
  uint8_t addr[16];
  int sortkey;
};

int __lookup_name(struct address *buf, char *canon, const char *name, int family, int flags)
{
  (void)flags;
  wx_addr_ip addrs[MAX_ADDRS];
  if (!name || !*name || strnlen(name, 255) >= 255) return EAI_NONAME;
  int n = resolve(name, family, addrs);
  if (n < 0) return n;
  strcpy(canon, name);
  for (int i = 0; i < n; i++) {
    memset(&buf[i], 0, sizeof buf[i]);
    buf[i].family = addrs[i].tag == AF_WX_INET4 ? AF_INET : AF_INET6;
    memcpy(buf[i].addr, addrs[i].u.inet6, buf[i].family == AF_INET ? 4 : 16);
  }
  return n;
}
