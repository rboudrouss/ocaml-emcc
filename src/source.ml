(* The sources a recipe builds (its SOURCE, see driver.sh), copied to a
   fresh directory.  Each function returns the version of the sources, the
   first field of the recipe's stamp.  Downloads and clones are cached in
   $SYSROOT/src.  Commands' stdout goes to stderr: `ocaml-emcc internal`
   prints results on stdout. *)

let sh prog args = Env.run_exn ~out:Unix.stderr prog args
let ok prog args = Env.run ~out:Unix.stderr prog args = 0

let copy src dest = sh "cp" [ "-a"; src; dest ]
let remove p = sh "rm" [ "-rf"; p ]
let rename a b = sh "mv" [ a; b ]
let is_dir d = Sys.file_exists d && Sys.is_directory d

let cache rel =
  let d = Env.sysroot_file "src" in
  if not (is_dir d) then sh "mkdir" [ "-p"; d ];
  Filename.concat d rel

let opam args = Env.run ~env:(Switch.opam_env ()) ~out:Unix.stderr "opam" args = 0
let opam_capture args = Env.capture ~env:(Switch.opam_env ()) "opam" args

(* ------------------------------------------------------------ versions *)

(* `sort -V` order: digit runs compared as numbers *)
let compare_versions a b =
  let n = String.length a and m = String.length b in
  let is_digit c = c >= '0' && c <= '9' in
  let run s i k = let j = ref i in while !j < k && is_digit s.[!j] = is_digit s.[i] do incr j done; !j in
  let rec go i j =
    if i >= n || j >= m then compare (n - i) (m - j)
    else
      let i' = run a i n and j' = run b j m in
      let x = String.sub a i (i' - i) and y = String.sub b j (j' - j) in
      let c =
        if is_digit a.[i] && is_digit b.[j] then
          let strip s = let k = ref 0 in while !k < String.length s - 1 && s.[!k] = '0' do incr k done; String.sub s !k (String.length s - !k) in
          let x = strip x and y = strip y in
          compare (String.length x, x) (String.length y, y)
        else compare x y
      in
      if c <> 0 then c else go i' j'
  in
  go 0 0

(* Whether [v] is compatible with [want]: [want] itself, or a version
   starting with it ("6" -> 6.3.0, 6-1); any version when [want] is "" *)
let version_matches want v =
  want = ""
  || Str_util.starts_with ~prefix:want v
     && (String.length v = String.length want || List.mem v.[String.length want] [ '.'; '-'; ' ' ])

(* The lines of [lines] ("<version> ...") whose version matches [want] *)
let version_match want lines = List.filter (version_matches want) lines

(* The version wanted for a host library [hv] (COMPAT) *)
let wanted ~compat hv =
  let fields n = String.concat "." (Compat.filteri (fun i _ -> i < n) (String.split_on_char '.' hv)) in
  match compat with
  | "" | "major" -> Some (fields 1)
  | "minor" -> Some (fields 2)
  | "exact" -> Some hv
  | "latest" -> Some ""
  | _ -> None

(* "<version> <file>" for each <prefix>-<version>.tar.{xz,bz2,gz} named in
   a directory listing, oldest first, xz preferred *)
let release_files prefix listing =
  let n = String.length listing and key = prefix ^ "-" in
  let is_v c = (c >= '0' && c <= '9') || c = '.' in
  let is_digit c = c >= '0' && c <= '9' in
  let rec scan acc i =
    match Str_util.find (String.sub listing i (n - i)) key with
    | None -> acc
    | Some k ->
        let a = i + k + String.length key in
        let j = ref a in
        while !j < n && is_v listing.[!j] do incr j done;
        (* <version>.tar.<ext>: the version ends with a digit *)
        let chunk = String.sub listing a (!j - a) in
        let l = String.length chunk in
        let acc =
          if l >= 2 && chunk.[l - 1] = '.' && is_digit chunk.[0] && is_digit chunk.[l - 2] then
            let v = String.sub chunk 0 (l - 1) and after = String.sub listing !j (min 7 (n - !j)) in
            match List.find_opt (fun (e, _) -> Str_util.starts_with ~prefix:("tar." ^ e) after) [ ("xz", 1); ("bz2", 2); ("gz", 3) ] with
            | Some (e, rank) -> (v, rank, Printf.sprintf "%s%s.tar.%s" key v e) :: acc
            | None -> acc
          else acc
        in
        scan acc a
  in
  List.sort (fun (v, r, _) (w, s, _) -> match compare_versions v w with 0 -> compare r s | c -> c) (scan [] 0)
  |> List.fold_left (fun acc (v, _, f) -> match acc with (w, _) :: _ when w = v -> acc | _ -> (v, f) :: acc) []
  |> List.rev
  |> List.map (fun (v, f) -> v ^ " " ^ f)

(* The value of each macro in the output of `cc -E -dM`, quotes removed *)
let macro_values defs macros =
  let lines = String.split_on_char '\n' defs in
  let value m =
    Compat.find_map
      (fun l ->
        match Str_util.words l with
        | "#define" :: name :: v :: _ when name = m -> Some (String.concat "" (String.split_on_char '"' v))
        | _ -> None)
      lines
  in
  let vs = List.map value macros in
  if List.mem None vs then None else Some (String.concat "." (List.map Option.get vs))

(* The version of a C library as the host (hence the native build) sees
   it: pkg-config, else the version macros of its header. *)
let host_version pc header macros =
  let from_pc =
    if Env.which "pkg-config" = None then None
    else match Env.capture "pkg-config" [ "--modversion"; pc ] with Some v when String.trim v <> "" -> Some (String.trim v) | _ -> None
  in
  match from_pc with
  | Some v -> Some v
  | None when header = "" -> None
  | None -> (
      let src = Filename.temp_file "ocaml-emcc" ".c" in
      Compat.write_file src (Printf.sprintf "#include <%s>\n" header);
      let defs = Env.capture "cc" [ "-E"; "-dM"; src ] in
      Sys.remove src;
      match defs with Some d -> macro_values d macros | None -> None)

(* --------------------------------------------------------------- fetch *)

(* The sources of the installed opam package [pkg]: the build dir kept by
   opam (OPAMKEEPBUILDDIR / keep-build-dir), the sources of pinned
   packages, else `opam source`, which applies the `patches:` of the opam
   file as opam does in this switch.  Not the archive opam keeps in
   .opam-switch/sources: they are not applied there (mlcuddidl's
   exn_init_val_unit.diff). *)
let opam_source pkg dest =
  let ver = match Switch.version pkg with Some v -> v | None -> Env.fail "%s is not installed in %s" pkg (Switch.prefix ()) in
  let kept = List.find_opt is_dir [ Switch.opam_file ("build/" ^ pkg ^ "." ^ ver); Switch.opam_file ("sources/" ^ pkg) ] in
  (match kept with
  | Some src ->
      Env.log "using sources of %s.%s from %s" pkg ver src;
      copy src dest
  | None ->
      let c = cache (pkg ^ "." ^ ver) in
      if not (is_dir c) then (
        Env.log "sources of %s.%s not kept in the switch, running opam source" pkg ver;
        remove (c ^ ".tmp");
        if not (opam [ "source"; pkg ^ "." ^ ver; "--dir"; c ^ ".tmp" ]) then Env.fail "opam source %s.%s failed" pkg ver;
        rename (c ^ ".tmp") c);
      copy c dest);
  ver

(* The sources of any version known to the opam repository, installed or
   not (opam checks the archive checksum); false if it has no such
   version. *)
let opam_version pkg ver dest =
  let c = cache (pkg ^ "." ^ ver) in
  let available =
    is_dir c
    || opam_capture [ "show"; "--field=version"; pkg ^ "." ^ ver ] <> None
       && (Env.log "fetching %s.%s with opam source" pkg ver;
           remove (c ^ ".tmp");
           opam [ "source"; pkg ^ "." ^ ver; "--dir"; c ^ ".tmp" ] && (rename (c ^ ".tmp") c; true))
  in
  if available then copy c dest;
  available

(* A tarball, extracted without its top directory; checked against
   [sha256] if given *)
let url ?(sha256 = "") u dest =
  let file = cache (Filename.basename u) in
  if not (Sys.file_exists file) then (
    Env.log "downloading %s" u;
    if not (ok "curl" [ "-fsSL"; "--retry"; "3"; "-o"; file ^ ".tmp"; u ]) then (
      (try Sys.remove (file ^ ".tmp") with Sys_error _ -> ());
      Env.fail "cannot download %s" u);
    rename (file ^ ".tmp") file);
  if sha256 <> "" then (
    match Env.capture "sha256sum" [ file ] with
    | Some s when Str_util.words s <> [] && List.hd (Str_util.words s) = sha256 -> ()
    | _ -> Sys.remove file; Env.fail "checksum mismatch for %s" u);
  sh "mkdir" [ "-p"; dest ];
  sh "tar" [ "-xf"; file; "-C"; dest; "--strip-components=1" ];
  Filename.basename u

(* A shallow clone, without history.  Tags and branches go through `clone
   --branch`; commits through `fetch --depth 1 <sha>`, which GitHub and
   GitLab allow.  Clones are cached per (repository, ref). *)
let git u ref_ dest =
  let base = Filename.basename u in
  let base = if Filename.check_suffix base ".git" then Filename.chop_suffix base ".git" else base in
  let c = cache (Filename.concat "git" (base ^ "-" ^ if ref_ = "" then "HEAD" else ref_)) in
  if not (is_dir c) then (
    Env.log "git clone --depth 1 %s%s" u (if ref_ = "" then "" else " (" ^ ref_ ^ ")");
    let tmp = c ^ ".tmp" in
    remove tmp;
    sh "mkdir" [ "-p"; Filename.dirname c ];
    let clone = [ "clone"; "-q"; "--depth"; "1"; "--recurse-submodules"; "--shallow-submodules" ] in
    if ref_ = "" then sh "git" (clone @ [ u; tmp ])
    else if Env.capture "git" (clone @ [ "--branch"; ref_; u; tmp ]) = None then (
      remove tmp;
      sh "mkdir" [ "-p"; tmp ];
      let in_tmp args = ok "git" ("-C" :: tmp :: args) in
      if
        not
          (in_tmp [ "init"; "-q" ]
          && in_tmp [ "remote"; "add"; "origin"; u ]
          && in_tmp [ "fetch"; "-q"; "--depth"; "1"; "origin"; ref_ ]
          && in_tmp [ "checkout"; "-q"; "FETCH_HEAD" ]
          && in_tmp [ "submodule"; "-q"; "update"; "--init"; "--depth"; "1"; "--recursive" ])
      then (remove tmp; Env.fail "cannot fetch %s from %s" ref_ u));
    rename tmp c);
  copy c dest;
  if ref_ = "" then "HEAD" else ref_

(* The compiler sources: whichever compiler package of the switch carries
   them.  Since OCaml 5.3 they live in `ocaml-compiler` (ocaml-base-compiler
   is a meta package), hence the order. *)
let ocaml dest =
  let pkgs = [ "ocaml-variants"; "ocaml-compiler"; "ocaml-base-compiler" ] in
  let kept p = match Switch.version p with Some v -> is_dir (Switch.opam_file ("build/" ^ p ^ "." ^ v)) | None -> false in
  match List.find_opt kept pkgs with
  | Some p -> opam_source p dest
  | None -> (
      match List.find_opt Switch.is_installed pkgs with
      | Some p -> opam_source p dest
      | None -> Env.fail "cannot find the compiler package of the switch")

(* An opam package wrapping the upstream sources: either they are the
   package's sources themselves, or the upstream tarball is inside (opam's
   `gmp`). *)
let unpack_vendored src prefix dest =
  if Sys.file_exists (Filename.concat src "configure") then rename src dest
  else
    let rec find depth dir =
      if depth > 3 then None
      else
        let entries = try List.sort compare (Array.to_list (Sys.readdir dir)) with Sys_error _ -> [] in
        match
          List.find_opt
            (fun e -> Str_util.starts_with ~prefix:(prefix ^ "-") e && Str_util.find e ".tar." <> None)
            entries
        with
        | Some e -> Some (Filename.concat dir e)
        | None -> Compat.find_map (fun e -> let d = Filename.concat dir e in if is_dir d then find (depth + 1) d else None) entries
    in
    match find 1 src with
    | None -> Env.fail "no %s sources in %s" prefix src
    | Some t ->
        sh "mkdir" [ "-p"; dest ];
        sh "tar" [ "-xf"; t; "-C"; dest; "--strip-components=1" ];
        remove src

(* SOURCE=system:<name>, for C libraries that opam packages take from the
   system (conf-<name>); see "system libraries" in driver.sh.  The sources
   of OPAM_SOURCES if the switch has it installed (what the project links
   natively).  Otherwise the newest upstream release compatible with the
   host's version (any version without a host library), fetched through
   opam when opam knows it (checksum verified).  [releases]: the
   "<version> <url>" lines of the recipe's `releases` function, if any. *)
let system ~var ~releases name dest =
  let prefix = match var "TARBALL" with "" -> name | t -> t in
  let opam_sources = var "OPAM_SOURCES" and header = var "HEADER" and pkgconfig = var "PKGCONFIG" in
  let rels = var "RELEASES" in
  if opam_sources <> "" && Switch.is_installed opam_sources then (
    let v = opam_source opam_sources (dest ^ ".opam") in
    unpack_vendored (dest ^ ".opam") prefix dest;
    v)
  else
    let host =
      if header = "" && pkgconfig = "" then None
      else host_version (if pkgconfig = "" then name else pkgconfig) header (Str_util.words (var "VERSION_MACROS"))
    in
    let want =
      match host with
      | Some hv -> (
          match wanted ~compat:(var "COMPAT") hv with
          | Some w ->
              Env.log "host %s is %s: using the newest %srelease" name hv (if w = "" then "" else w ^ ".x ");
              w
          | None -> Env.fail "%s: bad COMPAT '%s'" name (var "COMPAT"))
      | None ->
          Env.log "no host %s found (pkg-config%s): using the newest release" name (if header = "" then "" else ", " ^ header);
          ""
    in
    let candidates =
      match releases with
      | Some lines -> lines
      | None when rels <> "" -> (
          match Env.capture "curl" [ "-fsL"; "--retry"; "3"; rels ] with Some l -> release_files prefix l | None -> [])
      | None -> []
    in
    let last l = match List.rev l with x :: _ -> Some x | [] -> None in
    let v, file =
      match Option.map Str_util.words (last (version_match want candidates)) with
      | Some (v :: f :: _) -> (v, f)
      | Some [ v ] -> (v, "")
      | _ -> ("", "")
    in
    let from_opam =
      if opam_sources = "" then None
      else
        (* opam versions may carry a packaging revision (6.3.0-1) *)
        let all = match opam_capture [ "show"; "--field=all-versions"; opam_sources ] with Some s -> Str_util.words (String.map (fun c -> if c = '\n' then ' ' else c) s) | None -> [] in
        match last (version_match (if v = "" then want else v) all) with
        | Some ov
          when (v = "" || List.hd (String.split_on_char '-' ov) = v) && opam_version opam_sources ov (dest ^ ".opam") ->
            unpack_vendored (dest ^ ".opam") prefix dest;
            Some ov
        | _ -> None
    in
    match from_opam with
    | Some ov -> ov
    | None ->
        if v = "" then
          Env.fail "%s: no release found%s (%s)" name (if want = "" then "" else " for version " ^ want)
            (if rels = "" then "no RELEASES" else rels);
        Env.log "%s %s: not in the opam repository, downloading it (no checksum to verify)" prefix v;
        let file =
          if Str_util.find file "://" <> None then file
          else
            let r = if Filename.check_suffix rels "/" then String.sub rels 0 (String.length rels - 1) else rels in
            r ^ "/" ^ file
        in
        ignore (url file dest);
        v
