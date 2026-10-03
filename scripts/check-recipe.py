#!/usr/bin/env python3
"""Validate source pins and Dockerfile inputs without QNX or network access."""

from __future__ import annotations

import pathlib
import re
import shlex
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "sources.manifest"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    global FAILED
    FAILED = True


FAILED = False
rows: dict[str, tuple[str, str, str, str]] = {}
dirs: set[str] = set()
for number, raw in enumerate(MANIFEST.read_text().splitlines(), 1):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    fields = [field.strip() for field in raw.split("|")]
    if len(fields) != 6:
        fail(f"sources.manifest:{number}: expected six fields")
        continue
    name, kind, directory, revision, upstream, _mirror = fields
    if name in rows:
        fail(f"sources.manifest:{number}: duplicate name {name}")
    if directory in dirs and not directory.startswith("("):
        fail(f"sources.manifest:{number}: duplicate path {directory}")
    rows[name] = (kind, directory, revision, upstream)
    dirs.add(directory)
    if kind == "tar" and not re.fullmatch(r"[0-9a-f]{64}", revision):
        fail(f"sources.manifest:{number}: invalid SHA-256 for {name}")
    if kind == "git" and not re.fullmatch(r"[0-9a-f]{40}", revision):
        fail(f"sources.manifest:{number}: invalid commit for {name}")
    if kind == "crate" and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", revision):
        fail(f"sources.manifest:{number}: invalid crate version for {name}")
    if upstream.startswith("http://"):
        fail(f"sources.manifest:{number}: insecure public URL for {name}")


def require_text(path: str, value: str, description: str) -> None:
    text = (ROOT / path).read_text()
    if value not in text:
        fail(f"{path}: missing manifest {description} {value}")


require_text("Dockerfile", rows["ubuntu-base"][2], "Ubuntu digest")
require_text("Dockerfile.gcc16", rows["gcc-16.1.0"][2], "GCC 16 SHA-256")
require_text("Dockerfile.tools", rows["meson-1.8.2"][2], "Meson SHA-256")
require_text("build-toolchain.sh", rows["gcc-qnx"][2], "GCC 11 commit")
require_text("Dockerfile.rust", rows["rust-1.99.0-qnx650"][2], "Rust commit")
require_text(
    "Dockerfile.rust",
    rows["rust-ci-llvm-1.99.0"][3].split("/")[-2],
    "CI LLVM commit",
)
require_text("Dockerfile.rust", rows["rust-libc-0.2.189-qnx650"][2], "libc commit")
require_text("Dockerfile.rust", rows["cc-rs-1.4.3-qnx650"][2], "cc-rs commit")
require_text(
    "Dockerfile.compiler",
    f"CARGO_AUDIT_VERSION={rows['cargo-audit'][2]}",
    "cargo-audit version",
)
require_text("runner/Dockerfile", rows["github-runner-2.337.0"][2], "runner SHA-256")
require_text(
    "runner/Dockerfile", rows["github-runner-ubuntu-base"][2], "runner base digest"
)


def logical_lines(text: str) -> list[str]:
    result: list[str] = []
    current = ""
    for raw in text.splitlines():
        stripped = raw.strip()
        if not current and (not stripped or stripped.startswith("#")):
            continue
        current += (" " if current else "") + stripped.rstrip("\\").strip()
        if not stripped.endswith("\\"):
            result.append(current)
            current = ""
    if current:
        result.append(current)
    return result


for dockerfile in sorted(ROOT.rglob("Dockerfile*")):
    if dockerfile.relative_to(ROOT).parts[0] in ("gcc-work", "rust-work"):
        continue
    for line in logical_lines(dockerfile.read_text()):
        if not line.upper().startswith(("COPY ", "ADD ")):
            continue
        words = shlex.split(line)
        args = words[1:]
        while args and args[0].startswith("--"):
            args.pop(0)
        if "--from=" in line or len(args) < 2:
            continue
        for source in args[:-1]:
            if "$" in source or "*" in source:
                continue
            if not (ROOT / source).exists():
                manifest_input = any(
                    kind == "tar" and directory == source
                    for kind, directory, _revision, _upstream in rows.values()
                )
                if not manifest_input:
                    fail(f"{dockerfile.name}: missing COPY source {source}")
            if source.startswith(("gcc-work/", "rust-work/")):
                fail(f"{dockerfile.name}: COPY depends on ignored workspace {source}")

if FAILED:
    sys.exit(1)
print("recipe consistency checks passed")
