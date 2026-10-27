# Apply a unified diff by content instead of line numbers.
#   awk -f patch.awk FILE.patch      (in the directory the paths start from,
#                                     after their first component: patch -p1)
#
# Each hunk is placed where its old text (context and `-` lines) is, which
# must occur exactly once in the file: the line numbers of `@@` lines are
# ignored and may be left out (a bare `@@`).  A hunk whose old text is
# missing but whose new text is there is already applied, and skipped.  So
# a hunk keeps applying when the code moves or changes around it, and a
# change that would make it ambiguous stops the build instead of patching
# the wrong place.
#
# The text before the first `--- ` line describes the patch.  A hunk with
# line counts (`@@ -12,7 +12,9 @@`) ends after them; without, at the next
# `@@` or file, ignoring trailing empty lines.  An empty line in a hunk is
# an empty context line.  `--- /dev/null` creates a file.

function fail(msg) { printf "%s: %s\n", PATCH, msg > "/dev/stderr"; failed = 1; exit 1 }

function strip1(p) { sub(/[\t].*$/, "", p); if (p == "/dev/null") return p; sub(/^[^\/]*\//, "", p); return p }

# occurrences of seq[1..n] in buf[1..nbuf]; the first one in `at`
function find(seq, n,    i, j, c) {
  c = 0
  for (i = 1; i + n - 1 <= nbuf; i++) {
    for (j = 1; j <= n && buf[i + j - 1] == seq[j]; j++) ;
    if (j > n) { if (c == 0) at = i; c++ }
  }
  return c
}

function load(f,    line, r) {
  nbuf = 0
  if (f == "") return
  while ((r = (getline line < f)) > 0) buf[++nbuf] = line
  if (r < 0) fail("cannot read " f)
  close(f)
}

# in place, which keeps the file's mode (an executable configure)
function save(f,    i) {
  printf "" > f
  for (i = 1; i <= nbuf; i++) print buf[i] > f
  if (close(f) != 0) fail("cannot write " f)
}

# apply hunk number h of the current file to buf
function apply(h,    no, nn, i, c, cn, d) {
  no = nold; nn = nnew
  if (no == 0 && nbuf > 0) fail(file ": hunk " h " has no context to place it")
  c = find(old, no)
  if (c == 1) {
    d = nn - no
    if (d > 0) for (i = nbuf; i >= at + no; i--) buf[i + d] = buf[i]
    if (d < 0) for (i = at + no; i <= nbuf; i++) buf[i + d] = buf[i]
    nbuf += d
    for (i = 1; i <= nn; i++) buf[at + i - 1] = new[i]
    applied++
    return
  }
  if (c > 1) fail(file ": hunk " h " matches " c " places, add context to tell them apart")
  cn = nn > 0 ? find(new, nn) : 0
  if (cn == 1) { skipped++; return }
  fail(file ": hunk " h " does not match:\n" text)
}

function end_hunk() {
  if (!inhunk) return
  # without line counts, the empty lines at the end separate it from what follows
  if (!counted) { nold -= lastempty; nnew -= lastempty }
  apply(++hunk)
  inhunk = 0
}

function end_file() {
  end_hunk()
  if (file != "" && file != "/dev/null") save(file)
  file = ""
}

{ L[NR] = $0 }

END {
  if (failed) exit 1
  PATCH = FILENAME
  for (n = 1; n <= NR; n++) {
    line = L[n]
    if (substr(line, 1, 4) == "--- " && substr(L[n + 1], 1, 4) == "+++ " && !(inhunk && counted && (rold > 0 || rnew > 0))) {
      end_file()
      src = strip1(substr(line, 5)); dst = strip1(substr(L[n + 1], 5)); n++
      file = dst == "/dev/null" ? src : dst
      if (file == "/dev/null") fail("no file name")
      load(src == "/dev/null" ? "" : file)
      hunk = 0; nfiles++
      continue
    }
    if (file == "") continue          # description, diff/index lines
    if (substr(line, 1, 2) == "@@" && !(inhunk && counted && (rold > 0 || rnew > 0))) {
      end_hunk()
      inhunk = 1; nold = 0; nnew = 0; text = ""; lastempty = 0
      counted = match(line, /^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/)
      if (counted) {
        h = substr(line, 4, RLENGTH - 6); split(h, parts, " ")
        rold = split(substr(parts[1], 2), a, ",") > 1 ? a[2] + 0 : 1
        rnew = split(substr(parts[2], 2), a, ",") > 1 ? a[2] + 0 : 1
      }
      continue
    }
    if (!inhunk) continue
    if (counted && rold <= 0 && rnew <= 0) continue   # after the hunk
    c = substr(line, 1, 1); rest = substr(line, 2)
    if (c == "\\") continue           # \ No newline at end of file
    text = text line "\n"
    if (line == "") { c = " "; lastempty++ } else lastempty = 0
    if (c == " ") { old[++nold] = rest; new[++nnew] = rest; rold--; rnew-- }
    else if (c == "-") { old[++nold] = rest; rold-- }
    else if (c == "+") { new[++nnew] = rest; rnew-- }
    else if (counted) fail(file ": hunk " hunk + 1 " is shorter than its line counts")
    else { text = substr(text, 1, length(text) - length(line) - 1); end_hunk() }
  }
  end_file()
  if (nfiles == 0) fail("no file to patch")
  if (applied == 0 && skipped > 0) print "already applied"
}
