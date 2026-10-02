#!/usr/bin/env python3
# gcc11: default the DRIVER to -mno-unaligned-access.
#
# QNX 6.5 on ARMv7 runs the CPU with strict alignment checking (SCTLR.A=1);
# GCC's ARMv7 default -munaligned-access merges adjacent byte stores into
# unaligned halfword/word ops -> SIGBUS BUS_ADRALN. Project build recipes
# pass -mno-unaligned-access manually, but the TOOLCHAIN's OWN target libs
# were built without it (seen on a target as SIGBUS in libstdc++'s
# _ZSt11_Hash_bytes word-at-a-time loop -- an archive no project flag can
# fix), and any compile that forgets the flag re-introduces the fault class.
# The gcc-builder stage builds the target libs with the flag; this script
# appends %{!munaligned-access:-mno-unaligned-access}
# to the *cc1 and *cc1plus specs so the flag is the DEFAULT; an explicit
# -munaligned-access still opts back in.
#
# Runs AFTER gcc11-exidx-specs.py, which wrote the full -dumpspecs dump with
# the *link exidx append. Re-dump here would LOSE that edit, so edit the
# existing file in place (and regenerate + re-add the exidx append if the
# file is ever missing). The libdir specs file must stay a COMPLETE dump.
import os
import subprocess
from pathlib import Path

T = "arm-unknown-nto-qnx6.5.0eabi"
V = "11.2.0"
P = "/opt/gcc11"

out = f"{P}/lib/gcc/{T}/{V}/specs"
if os.path.exists(out):
    specs = Path(out).read_text()
else:
    specs = subprocess.check_output([f"{P}/bin/{T}-gcc", "-dumpspecs"]).decode()


def append_spec(specs, name, add):
    i = specs.index(f"*{name}:\n")
    j = specs.index("\n", i + len(name) + 3)
    if add not in specs[i:j]:
        specs = specs[:j] + add + specs[j:]
    return specs


specs = append_spec(specs, "link", " %{!r:%{!T*:-T exidx-merge.ld%s}}")
for spec in ("cc1", "cc1plus"):
    specs = append_spec(specs, spec, " %{!munaligned-access:-mno-unaligned-access}")
Path(out).write_text(specs)
print(f"wrote {out} (*cc1/*cc1plus += -mno-unaligned-access default)")

# --- verification 1: with NO flags, adjacent byte stores must NOT merge
# --- into an unaligned strh (the exact fault pattern seen on a target).
Path("/tmp/ua-check.c").write_text(
    "struct S { char a; char b; };\nvoid f(struct S *p) { p->a = 1; p->b = 2; }\n"
)
Path("/tmp/ua-check.cpp").write_text(
    "struct S { char a; char b; };\nvoid f(S *p) { p->a = 1; p->b = 2; }\n"
)
for drv, src2 in (
    (f"{P}/bin/{T}-gcc", "/tmp/ua-check.c"),
    (f"{P}/bin/{T}-g++", "/tmp/ua-check.cpp"),
):
    asm = subprocess.check_output([drv, "-O2", "-S", "-o", "-", src2]).decode()
    assert "strh" not in asm, f"{drv}: byte stores still merged (strh)"
    assert asm.count("strb") >= 2, f"{drv}: expected two strb byte stores"
print("verified: driver defaults to -mno-unaligned-access (C and C++)")

# --- verification 2: the shipped libstdc++.a must contain no
# --- unaligned-capable word loads in _Hash_bytes (byte-wise path only).
objdump = f"{P}/bin/{T}-objdump"
dis = subprocess.check_output([objdump, "-d", f"{P}/{T}/lib/libstdc++.a"]).decode()
lines = dis.splitlines()
inf = False
words = []
for line in lines:
    if "<_ZSt11_Hash_bytesPKvjj>:" in line:
        inf = True
        continue
    if inf and ("Disassembly" in line or (">:" in line and "Hash_bytes" not in line)):
        break
    if inf and "\tldr\t" in line and "[sp" not in line:
        words.append(line.strip())
assert not words, f"_Hash_bytes still has non-stack word loads: {words}"
print("verified: libstdc++.a _Hash_bytes is byte-wise (no unaligned ldr)")
