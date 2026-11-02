// ocaml-emcc: /etc/localtime in the program's file system, which libraries
// read for the local time zone (core's Timezone.local).  Under node, the
// host's (and the zone file of $TZ, as /usr/share/zoneinfo/$TZ); in
// browsers, or without one, a tzfile of the JavaScript engine's time zone
// from 1970 to 2037, whose offsets are Date's.  Not with -sNODERAWFS (the
// real files already).
var ocamlEmccLocaltime = {
  // the offset from UTC (seconds) at time t (seconds)
  offset(t) {
    return -new Date(t * 1000).getTimezoneOffset() * 60;
  },

  abbreviation(t, offset) {
    try {
      var part = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short' })
        .formatToParts(new Date(t * 1000)).find((p) => p.type == 'timeZoneName');
      if (part && /^[A-Za-z0-9+-]{3,}$/.test(part.value)) return part.value;
    } catch (e) {}
    var a = Math.abs(offset), h = Math.floor(a / 3600), m = Math.floor((a % 3600) / 60);
    return (offset < 0 ? '-' : '+') + String(h).padStart(2, '0') + (m ? String(m).padStart(2, '0') : '');
  },

  // a tzfile (version 1, RFC 8536) of the engine's time zone
  tzfile() {
    var L = ocamlEmccLocaltime, start = Date.UTC(1970, 0, 1) / 1000, end = Date.UTC(2038, 0, 1) / 1000 - 1;
    var step = 7 * 86400, types = [], times = [], indexes = [], chars = '';
    var type = (t) => {
      var o = L.offset(t), y = new Date(t * 1000).getUTCFullYear();
      // daylight saving: more than the least offset of the year
      var std = Math.min(L.offset(Date.UTC(y, 0, 1) / 1000), L.offset(Date.UTC(y, 6, 1) / 1000));
      var dst = o > std ? 1 : 0, abbr = L.abbreviation(t, o);
      var i = types.findIndex((x) => x.offset == o && x.dst == dst && x.abbr == abbr);
      if (i < 0) {
        var at = chars.indexOf(abbr + '\0');
        if (at < 0) { at = chars.length; chars += abbr + '\0'; }
        types.push({ offset: o, dst, abbr, at });
        i = types.length - 1;
      }
      return i;
    };
    var prev = L.offset(start);
    type(start);
    for (var t = start + step; t <= end + step; t += step) {
      var u = Math.min(t, end), o = L.offset(u);
      if (o == prev) continue;
      // the second the offset changes
      var lo = u - step, hi = u;
      while (hi - lo > 1) {
        var mid = Math.floor((lo + hi) / 2);
        if (L.offset(mid) == prev) lo = mid; else hi = mid;
      }
      times.push(hi);
      indexes.push(type(hi));
      prev = o;
    }
    var size = 44 + 5 * times.length + 6 * types.length + chars.length;
    var b = new Uint8Array(size), v = new DataView(b.buffer), p = 0;
    'TZif'.split('').forEach((c, i) => (b[i] = c.charCodeAt(0)));
    // version 1, then the counts: isut, isstd, leap, time, type, char
    [0, 0, 0, times.length, types.length, chars.length].forEach((n, i) => v.setUint32(20 + 4 * i, n));
    p = 44;
    times.forEach((t) => { v.setInt32(p, t); p += 4; });
    indexes.forEach((i) => (b[p++] = i));
    types.forEach((x) => { v.setInt32(p, x.offset); b[p + 4] = x.dst; b[p + 5] = x.at; p += 6; });
    for (var i = 0; i < chars.length; i++) b[p++] = chars.charCodeAt(i);
    return b;
  },

  install() {
    if (typeof FS == 'undefined') return;
    try { FS.stat('/etc/localtime'); return; } catch (e) {}
    var data = null;
    if (typeof process == 'object' && process.versions && process.versions.node && typeof require == 'function') {
      var fs = require('fs');
      try { data = fs.readFileSync('/etc/localtime'); } catch (e) {}
      var tz = process.env.TZ, dir = process.env.TZDIR || '/usr/share/zoneinfo';
      if (tz && /^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/.test(tz)) {
        try {
          var zone = fs.readFileSync(dir + '/' + tz), path = dir + '/' + tz;
          FS.mkdirTree(path.slice(0, path.lastIndexOf('/')));
          FS.writeFile(path, zone);
        } catch (e) {}
      }
    }
    try {
      if (!data) data = ocamlEmccLocaltime.tzfile();
      FS.mkdirTree('/etc');
      FS.writeFile('/etc/localtime', data);
    } catch (e) {}
  },
};
Module['preRun'] = [].concat(Module['preRun'] || [], () => ocamlEmccLocaltime.install());
