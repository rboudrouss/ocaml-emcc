mergeInto(LibraryManager.library, {
  oe_wat_apply: (h, arg, raised) => globalThis.__oe.apply(h, arg, raised),
  oe_wat_named_value: (name, len) => globalThis.__oe.named(name, len),
});
