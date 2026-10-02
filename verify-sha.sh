#!/usr/bin/env bash
# verify-sha.sh <file>... -- check a downloaded input against sources.manifest.
#
# Every toolchain input is fetched over the network; an unverified input
# silently undermines everything later compiled with the image.
#
# Exit 0 = matched (or not recorded, which warns); 1 = MISMATCH, treat as fatal.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/sources.manifest"
rc=0

for f in "$@"; do
    [ -f "$f" ] || { echo "verify-sha: $f does not exist" >&2; rc=1; continue; }
    b="$(basename "$f")"
    want="$(awk -F'|' -v b="$b" '
        /^[[:space:]]*(#|$)/ { next }
        { d = $3; r = $4; gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", r)
          n = split(d, seg, "/"); if (seg[n] == b) { print r; exit } }' "$MANIFEST" 2>/dev/null)"
    got="$(sha256sum "$f" | cut -d' ' -f1)"
    if [ -z "$want" ]; then
        echo "verify-sha: WARNING $b is not in sources.manifest (sha256 $got)" >&2
        continue
    fi
    if [ "$want" != "$got" ]; then
        echo "verify-sha: MISMATCH $b" >&2
        echo "  recorded $want" >&2
        echo "  actual   $got" >&2
        rc=1
    fi
done
exit $rc
