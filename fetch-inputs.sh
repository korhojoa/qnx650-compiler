#!/usr/bin/env bash
# fetch-inputs.sh -- download the build inputs that are not in git, and verify
# each one against sources.manifest.
#
# Dockerfile.tools does `COPY Python-2.7.18.tgz /tmp/`, so the image build
# needs that 17 MB archive in the build context. A binary of that size does
# not belong in git. Its URL and SHA-256 are in sources.manifest, and this
# script fetches it again when it is missing or does not match.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

while IFS='|' read -r name kind dir _rev url _mirror; do
    case "$name" in \#*|"") continue ;; esac
    kind="$(echo "$kind" | tr -d ' ')"; [ "$kind" = tar ] || continue
    dir="$(echo "$dir" | tr -d ' ')"; url="$(echo "$url" | tr -d ' ')"
    # ONLY files a Dockerfile COPYs from this directory. binutils/gcc/gcc-qnx
    # are fetched by the build scripts into their own work dirs -- pulling them
    # here just litters the repo (which this script did on its first run).
    grep -qE "^COPY +$dir" "$HERE"/Dockerfile* 2>/dev/null || continue
    case "$url" in http*) ;; *) continue ;; esac
    f="$HERE/$dir"
    if [ -f "$f" ]; then
        "$HERE/verify-sha.sh" "$f" && echo "ok       $dir" && continue
        echo "re-fetching $dir (failed verification)" >&2; rm -f "$f"
    fi
    echo ">> $dir"
    curl -fsSL -o "$f" "$url"
    "$HERE/verify-sha.sh" "$f" || { echo "FATAL: $dir does not match its pin" >&2; exit 1; }
    echo "fetched  $dir"
done < "$HERE/sources.manifest"
