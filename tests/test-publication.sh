#!/usr/bin/env bash
# Exercise upload failures and anonymous verification without network access.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
printf '{"schemaVersion":2}\n' > "$work/manifest.json"
digest="sha256:$(sha256sum "$work/manifest.json" | cut -d ' ' -f 1)"
printf -v GH_TOKEN '%s' upload-fixture-token
export GH_TOKEN
export REGISTRY_OWNER=Fixture REGISTRY_ACTOR=fixture
SOURCE_REVISION=$(printf 'a%.0s' {1..40})
export SOURCE_REVISION
export TEST_WORK="$work" TEST_DIGEST="$digest"
cat > "$work/bin/podman" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$1" >> "$TEST_WORK/calls"
case "$1" in
    run) [ "${TEST_IMAGE_FAIL:-0}" = 0 ] ;;
    login) cat > /dev/null ;;
    push)
        if [ "${TEST_PUSH_FAIL:-0}" = 1 ]; then exit 1; fi
        while [ "$#" -gt 0 ]; do
            if [ "$1" = --digestfile ]; then
                printf '%s\n' "$TEST_DIGEST" > "$2"
                break
            fi
            shift
        done ;;
    *) exit 2 ;;
esac
MOCK
cat > "$work/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
# An upload credential must never enter the anonymous access check.
for arg; do [[ $arg != *"$GH_TOKEN"* ]] || exit 99; done
if [ "${TEST_ACCESS_DENIED:-0}" = 1 ]; then exit 22; fi
case "${!#}" in
    https://ghcr.io/token) printf '{"token":"anonymous-fixture"}\n' ;;
    https://ghcr.io/v2/*/manifests/*) cat "$TEST_WORK/manifest.json" ;;
    *) exit 98 ;;
esac
MOCK
chmod 755 "$work/bin/"*
export PATH="$work/bin:$PATH"
reference="ghcr.io/fixture/qnx650-compiler@$digest"
"$root/scripts/check-public-image.sh" "$reference" > "$work/public.log"
if TEST_ACCESS_DENIED=1 "$root/scripts/check-public-image.sh" "$reference" > /dev/null 2>&1; then
    echo 'The public check accepted denied anonymous access.' >&2
    exit 1
fi
wrong="ghcr.io/fixture/qnx650-compiler@sha256:$(printf '0%.0s' {1..64})"
if "$root/scripts/check-public-image.sh" "$wrong" > /dev/null 2>&1; then
    echo 'The public check accepted a different manifest digest.' >&2
    exit 1
fi
"$root/scripts/publish-compiler.sh" > "$work/upload.log"
grep -q '^push$' "$work/calls"
grep -q 'Public image manifest verified' "$work/upload.log"
: > "$work/calls"
status=0
TEST_ACCESS_DENIED=1 "$root/scripts/publish-compiler.sh" > "$work/private.log" 2>&1 || status=$?
[ "$status" = 3 ]
grep -q '^push$' "$work/calls"
grep -q 'Set package visibility to Public' "$work/private.log"
: > "$work/calls"
if TEST_IMAGE_FAIL=1 "$root/scripts/publish-compiler.sh" > /dev/null 2>&1; then exit 1; fi
if grep -qE '^login$|^push$' "$work/calls"; then
    echo 'The publisher uploaded an image after a failed image check.' >&2
    exit 1
fi
if TEST_PUSH_FAIL=1 "$root/scripts/publish-compiler.sh" > /dev/null 2>&1; then exit 1; fi
echo 'Publication tests passed'
