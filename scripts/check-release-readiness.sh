#!/usr/bin/env bash
# Checks that do not require QNX media, a licence, network access, or images.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
failed=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failed=1
}

for required in LICENSE THIRD_PARTY_NOTICES.md CONTRIBUTING.md SECURITY.md; do
    [ -f "$required" ] || fail "missing $required"
done

for required in LICENSES/GPL-3.0.txt \
    LICENSES/GCC-Runtime-Library-Exception-3.1.txt \
    LICENSES/Rust-MIT.txt LICENSES/libc-MIT.txt LICENSES/cc-rs-MIT.txt \
    LICENSES/backtrace-MIT.txt; do
    [ -f "$required" ] || fail "missing $required"
done

mapfile -t shell_scripts < <(grep -E '\.sh$' release-files.txt)
for script in "${shell_scripts[@]}"; do
    [ -f "$script" ] || continue
    bash -n "$script" || fail "shell syntax: $script"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=warning -x -- "${shell_scripts[@]}" || fail "ShellCheck"
else
    fail "shellcheck is not installed"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --check || fail "whitespace errors"
fi

private_pattern='192[.]168[.]|/home/'"'[^/]+'"'/|/run/media/'"'[^/]+'"'/'
if rg -n --hidden -g '!.git/**' -g '!docs/PUBLISHING.md' \
        "$private_pattern" .; then
    fail "private endpoint or personal absolute path"
fi

# Maintainer-private names (machines, companion repositories, hardware) must
# not reach the public tree. The pattern list itself is private: it lives in
# release-private-words.txt, which is never part of a release, so the check
# is skipped in a public checkout.
if [ -f release-private-words.txt ]; then
    mapfile -t release_paths < release-files.txt
    if rg -n -i -f release-private-words.txt -- "${release_paths[@]}"; then
        fail "private name in a release file (see release-private-words.txt)"
    fi
fi

if grep -E '\.(a|o|so|iso|tgz|tar\.(gz|xz|bz2)|zip)$' release-files.txt; then
    fail "tracked binary or downloaded archive"
fi

if rg -n '^COPY +(gcc-work|rust-work)/' Dockerfile*; then
    fail "Dockerfile depends on an ignored work directory"
fi

awk -F'|' '
    /^[[:space:]]*(#|$)/ { next }
    {
        kind=$2; rev=$4
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", kind)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", rev)
        if (kind == "tar" && rev !~ /^[0-9a-f]{64}$/) {
            print FNR ": invalid tar sha256: " rev > "/dev/stderr"
            bad=1
        }
        if (kind == "git" && rev !~ /^[0-9a-f]{40}$/) {
            print FNR ": invalid git commit: " rev > "/dev/stderr"
            bad=1
        }
    }
    END { exit bad }
' sources.manifest || fail "sources.manifest revisions"

python3 scripts/check-recipe.py || fail "recipe consistency"
tests/test-scripts.sh || fail "script tests"
tests/test-publication.sh || fail "publication tests"

while IFS= read -r path; do
    [ -e "$path" ] || fail "release allowlist path is missing: $path"
done < release-files.txt

if (( failed )); then
    exit 1
fi
echo "release-readiness checks passed"
