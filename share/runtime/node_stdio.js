// ocaml-emcc: under node, the standard streams of the program are those of
// the node process, as bytes.  emscripten's console streams decode output
// lines as UTF-8 and drop NUL bytes, and read stdin by chunks of 256 bytes
// decoded as UTF-8: binary data (Marshal, compressed output) and characters
// split between two chunks are corrupted.  Not with -sNODERAWFS (the real
// descriptors already), nor when the page or the user gives Module.print,
// Module.printErr or Module.stdin.
if (typeof process == 'object' && process.versions && process.versions.node &&
    typeof require == 'function') {
  Module['onRuntimeInitialized'] = (function (next) {
    return function () {
      var nodeFs = require('fs');
      var own = [Module['stdin'], Module['print'], Module['printErr']];
      [0, 1, 2].forEach(function (fd) {
        var stream = FS.getStream(fd);
        if (!stream || !stream.tty || own[fd]) return;
        var ops = Object.create(stream.stream_ops);
        // EAGAIN: a non-blocking pipe or terminal, try again
        var retry = function (f) {
          for (;;) {
            try { return f(); } catch (e) {
              if (e.code === 'EAGAIN') continue;
              if (e.code === 'EOF') return 0;
              throw new FS.ErrnoError(29 /* EIO */);
            }
          }
        };
        if (fd === 0)
          ops.read = function (stream, buffer, offset, length) {
            return retry(function () { return nodeFs.readSync(0, buffer, offset, length, null); });
          };
        else
          ops.write = function (stream, buffer, offset, length) {
            var done = 0;
            while (done < length)
              done += retry(function () { return nodeFs.writeSync(fd, buffer, offset + done, length - done); });
            return length;
          };
        stream.stream_ops = ops;
      });
      if (next) next();
    };
  })(Module['onRuntimeInitialized']);
}
