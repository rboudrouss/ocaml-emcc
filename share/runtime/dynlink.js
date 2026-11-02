// Linked (--js-library) by `ocaml-emcc link --dynlink` without --threads.
//
// A plugin reaches the variables of the program through the GOT, which
// emscripten fills with the program's exports.  Those of its thread-local
// variables (OCaml 5's caml_state; every object is compiled with -pthread)
// are offsets in the program's TLS block, which emscripten only turns into
// addresses in a program with threads: they are, before main.  The names
// are written in by `link`, from the program's dylink.0 section.
addToLibrary({
  $ocamlEmccTlsExports__deps: ['$GOT', 'ocaml_emcc_tls_base'],
  $ocamlEmccTlsExports__postset: 'addOnPreRun(ocamlEmccTlsExports);',
  $ocamlEmccTlsExports: () => {
    var names = ["__OCAML_EMCC_TLS_EXPORTS__"];
    var base = _ocaml_emcc_tls_base();
    for (var n of names) {
      var g = GOT[n];
      if (g) g.value = typeof g.value == 'bigint' ? g.value + BigInt(base) : g.value + Number(base);
    }
  },
});
