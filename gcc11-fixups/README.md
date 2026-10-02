# gcc11-fixups -- target libraries built with -mno-unaligned-access

## Why

QNX 6.5 on ARMv7 runs with strict alignment checking (SCTLR.A=1): every
unaligned load or store traps with SIGBUS. GCC defaults ARMv7 to
`-munaligned-access` and merges adjacent byte stores/loads into unaligned
halfword/word operations. Passing `-mno-unaligned-access` in a project's own
build is not enough, because the toolchain's own target libraries were built
with the default. A statically linked C++ binary then carries latent SIGBUS
faults that no project flag can fix. The observed case is libstdc++'s
`_ZSt11_Hash_bytes`, whose Murmur loop does `ldr r3, [r0], #4` from an
arbitrary string pointer.

## How the recipe builds the replacements

`build-toolchain.sh` builds the target libraries directly from the pinned
GCC 11 source during the `gcc-builder` stage, using the same gcc4-compatible
ABI and `CFLAGS_FOR_TARGET/CXXFLAGS_FOR_TARGET="-g -O2 -mno-unaligned-access"`:

- target libraries and compiler runtimes are generated, never committed;
- every libtool-dropped top-level `src/.libs/*.o` compatibility object is
  appended to `libstdc++.a` before the build stage is discarded;
- `gcc11-unaligned-specs.py` appends
  `%{!munaligned-access:-mno-unaligned-access}` to the `*cc1` and `*cc1plus`
  specs, editing the existing full-dump specs file from the exidx layer in
  place (re-dumping would lose the `*link` exidx append). It then verifies
  that flag-less gcc/g++ no longer merge byte stores (no `strh`) and that the
  installed `libstdc++.a` `_Hash_bytes` has no non-stack word loads. An
  explicit `-munaligned-access` still opts back in.

A disassembly scan of the rebuilt libstdc++, libsupc++, libgomp and libgcc
for odd-offset `ldrh`/`strh` and misaligned-offset word `ldr`/`str` reports
zero hits.

The x86 GCC 11 libraries keep their normal target flags; x86 has no
strict-alignment constraint.

## Not covered

The shared runtime libraries (`libstdc++.so.6`, `libgomp.so.1`) keep the
default unaligned code. Link with `-static-libstdc++ -static-libgcc` when
deploying C++ to a strict-alignment target. GCC 16 applies the same flags at
its source (`gcc16-port/container-build.sh`).
