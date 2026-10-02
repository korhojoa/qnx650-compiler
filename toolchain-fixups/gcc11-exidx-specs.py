#!/usr/bin/env python3
# Backport of the gcc16 .ARM.exidx fix to the gcc11 toolchain.
#
# binutils' armnto emulation ldscript predates ARM EHABI: it has no
# .ARM.exidx/.ARM.extab rules, so per-function exidx sections (any
# -ffunction-sections build, and gcc's own crt objects) stay scattered
# orphans and PT_ARM_EXIDX covers almost nothing. The runtime unwinder
# lives in QNX libc.so.3 and reads PT_ARM_EXIDX, so every C++ throw in a
# gcc11-built binary aborts. The gcc16 port found this latent defect.
# Fix: exidx-merge.ld (INSERT AFTER .text, canonical armelf.x rules),
# added to every link through the driver specs file.
#
# The auto-loaded libdir specs file must be a COMPLETE -dumpspecs dump. A
# partial file silently RESETS the builtin specs (endian defines vanish).
# Dump everything, edit *link only.
import subprocess
from pathlib import Path

T = "arm-unknown-nto-qnx6.5.0eabi"
V = "11.2.0"
P = "/opt/gcc11"

gcc = f"{P}/bin/{T}-gcc"
specs = subprocess.check_output([gcc, "-dumpspecs"]).decode()
add = " %{!r:%{!T*:-T exidx-merge.ld%s}}"
i = specs.index("*link:\n")
j = specs.index("\n", i + len("*link:\n"))
if add not in specs[i:j]:
    specs = specs[:j] + add + specs[j:]
out = f"{P}/lib/gcc/{T}/{V}/specs"
Path(out).write_text(specs)
print(f"wrote {out} (*link += exidx-merge.ld)")

# --- verification: throw/catch binary must carry ONE merged, fully-covered
# --- .ARM.exidx (build fails loudly here if the fix regresses)
src = "/tmp/exidx-check.cpp"
Path(src).write_text("""
#include <stdexcept>
#include <cstdio>
__attribute__((noinline)) int f1() { throw std::runtime_error("x"); }
__attribute__((noinline)) int f2() { try { return f1(); } catch (...) { return 7; } }
int main() { printf("%d\\n", f2()); return 0; }
""")
subprocess.check_call(
    [
        f"{P}/bin/{T}-g++",
        "-ffunction-sections",
        "-O2",
        "-static-libstdc++",
        "-static-libgcc",
        "-o",
        "/tmp/exidx-check",
        src,
    ]
)
readelf = f"{P}/bin/{T}-readelf"
secs = subprocess.check_output([readelf, "-S", "/tmp/exidx-check"]).decode()
exidx_secs = [l for l in secs.splitlines() if ".ARM.exidx" in l]
assert len(exidx_secs) == 1, f"expected 1 merged .ARM.exidx, got {len(exidx_secs)}"
parts = exidx_secs[0].split()
sec_size = int(parts[parts.index(".ARM.exidx") + 4], 16)
phdrs = subprocess.check_output([readelf, "-l", "/tmp/exidx-check"]).decode()
ph = [l for l in phdrs.splitlines() if "EXIDX" in l]
assert ph, "no PT_ARM_EXIDX program header"
ph_memsz = int(ph[0].split()[5], 16)
assert ph_memsz == sec_size, (
    f"PT_ARM_EXIDX MemSiz {ph_memsz:#x} != .ARM.exidx size {sec_size:#x}"
)
print(
    f"verified: single .ARM.exidx ({sec_size:#x} bytes), PT_ARM_EXIDX covers it fully"
)

# shared-lib link must also work under the new specs
subprocess.check_call(
    [
        f"{P}/bin/{T}-g++",
        "-shared",
        "-fPIC",
        "-o",
        "/tmp/exidx-check.so",
        src,
        "-static-libstdc++",
        "-static-libgcc",
    ]
)
print("shared-lib link OK under exidx specs")
