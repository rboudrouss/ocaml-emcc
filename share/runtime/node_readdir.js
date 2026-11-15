// Linked (--js-library) by `ocaml-emcc link` with -sNODERAWFS: readdir(3)
// without a stat per entry.  emscripten's getdents64 looks every entry up
// (lstat under NODERAWFS) for its type and inode: some 960 lstat per file
// ocamlc compiles, which lists the standard library, 6 % of its time.
// Here the types come from node's readdir (withFileTypes), as a native
// getdents64 gives them (emscripten's made FIFOs and sockets regular
// files).  d_ino is not the inode of the entry (node does not give it),
// but a hash of its path, never 0; "." and ".." keep theirs.
#if NODERAWFS
var OcamlEmccReaddir = {
  __syscall_getdents64__deps: ['$stringToUTF8', '$ERRNO_CODES'],
  __syscall_getdents64: (fd, dirp, count) => {
    var stream = SYSCALLS.getStreamFromFD(fd);
    if (!stream.getdents) {
      var entries;
      try {
        entries = fs.readdirSync(stream.path, { withFileTypes: true });
      } catch (e) {
        if (e.code in ERRNO_CODES) throw new FS.ErrnoError(ERRNO_CODES[e.code]);
        throw e;
      }
      stream.getdents = [null, null].concat(entries);
    }

    var struct_size = {{{ C_STRUCTS.dirent.__size__ }}};
    var pos = 0;
    var off = FS.llseek(stream, 0, {{{ cDefs.SEEK_CUR }}});

    var startIdx = Math.floor(off / struct_size);
    var endIdx = Math.min(stream.getdents.length, startIdx + Math.floor(count / struct_size));
    for (var idx = startIdx; idx < endIdx; idx++) {
      var id;
      var type;
      var name;
      var entry = stream.getdents[idx];
      if (idx === 0) {
        name = '.';
        id = stream.node.id;
        type = {{{ cDefs.DT_DIR }}};
      } else if (idx === 1) {
        name = '..';
        id = FS.lookupPath(stream.path, { parent: true }).node.id;
        type = {{{ cDefs.DT_DIR }}};
      } else {
        name = entry.name;
        // FNV-1a
        var path = stream.path + '/' + name;
        id = 0x811c9dc5;
        for (var i = 0; i < path.length; i++) id = Math.imul(id ^ path.charCodeAt(i), 0x01000193);
        id = (id >>> 0) || 1;
        type = entry.isDirectory() ? {{{ cDefs.DT_DIR }}} :
               entry.isSymbolicLink() ? {{{ cDefs.DT_LNK }}} :
               entry.isFile() ? {{{ cDefs.DT_REG }}} :
               entry.isCharacterDevice() ? {{{ cDefs.DT_CHR }}} :
               entry.isBlockDevice() ? 6 /* DT_BLK */ :
               entry.isFIFO() ? 1 /* DT_FIFO */ :
               entry.isSocket() ? 12 /* DT_SOCK */ :
               0 /* DT_UNKNOWN */;
      }
      {{{ makeSetValue('dirp + pos', C_STRUCTS.dirent.d_ino, 'id', 'i64') }}};
      {{{ makeSetValue('dirp + pos', C_STRUCTS.dirent.d_off, '(idx + 1) * struct_size', 'i64') }}};
      {{{ makeSetValue('dirp + pos', C_STRUCTS.dirent.d_reclen, C_STRUCTS.dirent.__size__, 'i16') }}};
      {{{ makeSetValue('dirp + pos', C_STRUCTS.dirent.d_type, 'type', 'i8') }}};
      stringToUTF8(name, dirp + pos + {{{ C_STRUCTS.dirent.d_name }}}, 256);
      pos += struct_size;
    }
    FS.llseek(stream, idx * struct_size, {{{ cDefs.SEEK_SET }}});
    return pos;
  },
};
// as emscripten's syscalls: errors returned as -errno, proxied to the main
// thread under -pthread
wrapSyscallFunction('__syscall_getdents64', OcamlEmccReaddir, false);
addToLibrary(OcamlEmccReaddir);
#endif
