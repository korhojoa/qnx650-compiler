#!/usr/bin/env python3
# gcc11: restore the stock-QNX static-libc second pass in *lib.
#
# QNX ships 100+ libc functions ONLY as static members of libc.a/libcS.a --
# regcomp/regexec/regfree, glob/globfree, wordexp, scandir, ... -- they are
# not exported by libc.so.3. The stock SDP 4.4 driver handles this: its
# link line is "-lc -Bstatic -lc", a second static pass that pulls those
# members on demand. The bigunclemax qnx_11_2 fork's LIB_SPEC lost that
# pass (ARM nto-eabi.h emits only -lc/-lcS; i386 nto.h only -lc), so any
# port using regex/glob/wordexp fails to link on gcc11 while linking fine
# on the stock 4.4 toolchain (verified in a container). Fix:
# append -l:libc.a (-lcS for pie, the PIC archive) to the exe branch of
# *lib. Members are pulled only for still-undefined symbols, so programs
# not using them are unchanged, and symbols already resolved from
# libc.so.3 stay dynamic -- exactly the stock -Bstatic -lc semantics.
# A comparison with the luka-dev/qnx65-armv7-toolchain repository, which
# has no license file, showed the gap. That toolchain adds a blanket
# -l:libc.a. This fix follows the stock 4.4 spec, not that code.
#
# ARM: runs AFTER gcc11-exidx-specs.py and gcc11-unaligned-specs.py, which
# maintain the installed COMPLETE -dumpspecs dump -- edit that file in
# place (re-dumping would lose their *link/*cc1 edits). x86: no specs file
# exists yet (neither fixup applies there), so install one -- a full dump
# with only *lib edited; a partial file would silently reset builtin specs.
import os
import subprocess
from pathlib import Path

P = "/opt/gcc11"
V = "11.2.0"
# An ARM-only base (Dockerfile.sdp-frida) sets QNX_TARGETS=arm and has no
# i386 driver. Skip a target only when QNX_TARGETS does not name it. Do not
# skip it because a file is missing.
TARGETS = os.environ.get("QNX_TARGETS", "arm x86").split()


def replace_spec(specs, name, old, new):
    i = specs.index(f"*{name}:\n")
    j = specs.index("\n", i + len(name) + 3)
    line = specs[i:j]
    if new in line:
        return specs  # already applied
    assert old in line, (
        f"*{name} spec changed upstream, expected: {old!r}, got: {line!r}"
    )
    return specs[:i] + line.replace(old, new) + specs[j:]


for arch, T, old, new in (
    (
        "arm",
        "arm-unknown-nto-qnx6.5.0eabi",
        "%{!symbolic: -lc %{shared:-lcS} %{pie:-lcS} %{no-pie:-lc}}",
        "%{!symbolic: -lc %{shared:-lcS} %{pie:-lcS} %{!shared:%{!pie:-l:libc.a}}}",
    ),
    (
        "x86",
        "i386-pc-nto-qnx6.5.0",
        "%{!shared:%{!symbolic:-lc}}",
        "%{!shared:%{!symbolic:-lc %{pie:-lcS} %{!pie:-l:libc.a}}}",
    ),
):
    if arch not in TARGETS:
        print(f"skipped {T}: not in QNX_TARGETS={TARGETS}")
        continue
    out = f"{P}/lib/gcc/{T}/{V}/specs"
    if os.path.exists(out):
        specs = Path(out).read_text()
    else:
        specs = subprocess.check_output([f"{P}/bin/{T}-gcc", "-dumpspecs"]).decode()
    specs = replace_spec(specs, "lib", old, new)
    Path(out).write_text(specs)
    print(f"wrote {out} (*lib exe branch += static libc.a pass)")

    # --- verification 1: a regcomp+glob program must now link flag-less,
    # --- with the symbols DEFINED (pulled from libc.a) and libc.so.3
    # --- still the dynamic base.
    Path("/tmp/slc-check.c").write_text(
        "#include <regex.h>\n#include <glob.h>\n"
        'int main(void){ regex_t r; regcomp(&r,"a.b",0); regfree(&r);\n'
        '  glob_t g; glob("/tmp/*",0,0,&g); globfree(&g); return 0; }\n'
    )
    subprocess.check_call(
        [f"{P}/bin/{T}-gcc", "-o", "/tmp/slc-check", "/tmp/slc-check.c"]
    )
    nm = subprocess.check_output([f"{P}/bin/{T}-nm", "/tmp/slc-check"]).decode()
    for sym in ("regcomp", "glob"):
        assert f" T {sym}\n" in nm, f"{T}: {sym} not statically resolved"
    dyn = subprocess.check_output(
        [f"{P}/bin/{T}-readelf", "-d", "/tmp/slc-check"]
    ).decode()
    assert "libc.so.3" in dyn, f"{T}: libc.so.3 no longer the dynamic base"
    print(f"verified: {T} regcomp/glob link statically, libc.so.3 dynamic")

    # --- verification 2: shared objects are UNCHANGED (no libc.a leak --
    # --- its non-PIC members would inject TEXTRELs into every .so).
    Path("/tmp/slc-so.c").write_text("int f(void){ return 1; }\n")
    subprocess.check_call(
        [
            f"{P}/bin/{T}-gcc",
            "-shared",
            "-fPIC",
            "-o",
            "/tmp/slc-so.so",
            "/tmp/slc-so.c",
        ]
    )
    dyn = subprocess.check_output(
        [f"{P}/bin/{T}-readelf", "-d", "/tmp/slc-so.so"]
    ).decode()
    assert "TEXTREL" not in dyn, f"{T}: shared link grew a TEXTREL"
    print(f"verified: {T} shared link unchanged (no TEXTREL)")

# --- verification 3: the earlier ARM spec edits must have survived the
# --- in-place rewrite (ordering guard -- this script must run LAST).
arm = Path(f"{P}/lib/gcc/arm-unknown-nto-qnx6.5.0eabi/{V}/specs").read_text()
assert "-T exidx-merge.ld" in arm, "ARM specs lost the exidx append"
assert "-mno-unaligned-access" in arm, "ARM specs lost the unaligned default"
print("verified: ARM exidx + unaligned spec edits intact")
