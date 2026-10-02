#!/usr/bin/env bash
# Build and audit the exact history-free source tree intended for publication.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-}

[ -n "$DEST" ] || {
    echo "usage: $0 <new-empty-directory>" >&2
    exit 2
}
if [ -e "$DEST" ]; then
    [ -d "$DEST" ] && [ -z "$(find "$DEST" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
        echo "destination must be a new or empty directory: $DEST" >&2
        exit 2
    }
else
    mkdir -p "$DEST"
fi
DEST=$(cd "$DEST" && pwd)
[ "$DEST" != "$ROOT" ] || { echo "refusing repository root" >&2; exit 2; }

cd "$ROOT"

mapfile -t current < <(
    git ls-files --cached --others --exclude-standard |
        while IFS= read -r path; do [ ! -e "$path" ] || printf '%s\n' "$path"; done |
        sort -u
)
# release-excluded.txt is the maintainer's private classification of paths
# that stay out of a release; a public checkout has none.
mapfile -t classified < <(cat release-files.txt release-excluded.txt 2>/dev/null | sort -u)
if ! diff -u <(printf '%s\n' "${classified[@]}") <(printf '%s\n' "${current[@]}"); then
    echo "release inventory contains unclassified or stale paths" >&2
    exit 1
fi

while IFS= read -r path; do
    [ -f "$path" ] || { echo "allowlisted path is not a regular file: $path" >&2; exit 1; }
    install -D -m "$(stat -c %a "$path")" "$path" "$DEST/$path"
done < release-files.txt

cd "$DEST"

# The public source snapshot is text-only. `file` catches renamed archives and
# objects instead of trusting extensions.
while IFS= read -r path; do
    description=$(file -b "$path")
    case "$description" in
        *ELF*|*archive*|*compressed*|*executable\ bytecode*)
            echo "forbidden non-source file: $path: $description" >&2
            exit 1
            ;;
    esac
done < release-files.txt

secret_pattern='192[.]168[.]|/home/'"'[^/]+'"'/|/run/media/'"'[^/]+'"'/|BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|[A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET)='
if rg -n --hidden -g '!.git/**' "$secret_pattern" .; then
    echo "possible credential, private endpoint, or personal path in snapshot" >&2
    exit 1
fi

scripts/check-release-readiness.sh
sort release-files.txt | xargs -d '\n' sha256sum > SOURCE-FILES.sha256
echo "release snapshot ready: $DEST"
