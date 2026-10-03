#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# gen-answers: valid input, restrictive output, and no key in stdout.
mkdir "$TMP/answers"
cp "$ROOT/gen-answers.sh" "$TMP/answers/"
key=ABCD-EFGH-IJKL-MNOP-QRST
printf '%s\n' "$key" > "$TMP/answers/license.key"
output=$("$TMP/answers/gen-answers.sh")
[[ $output != *"$key"* ]]
[[ $(stat -c %a "$TMP/answers/installer-answers.txt") == 600 ]]
[[ $(sed -n '3,7p' "$TMP/answers/installer-answers.txt" | paste -sd- -) == "$key" ]]
printf '%s\n' invalid > "$TMP/answers/license.key"
if "$TMP/answers/gen-answers.sh" >/dev/null 2>&1; then
    echo "gen-answers accepted an invalid key" >&2
    exit 1
fi

# verify-sha: matching and mismatching synthetic manifests.
mkdir "$TMP/verify"
cp "$ROOT/verify-sha.sh" "$TMP/verify/"
printf 'fixture\n' > "$TMP/verify/fixture.tar"
digest=$(sha256sum "$TMP/verify/fixture.tar" | cut -d' ' -f1)
printf 'fixture | tar | fixture.tar | %s | https://example.invalid/fixture.tar | -\n' \
    "$digest" > "$TMP/verify/sources.manifest"
"$TMP/verify/verify-sha.sh" "$TMP/verify/fixture.tar"
sed -i "s/$digest/0000000000000000000000000000000000000000000000000000000000000000/" \
    "$TMP/verify/sources.manifest"
if "$TMP/verify/verify-sha.sh" "$TMP/verify/fixture.tar" >/dev/null 2>&1; then
    echo "verify-sha accepted a mismatching file" >&2
    exit 1
fi

# build-compiler-image: REBUILD selects the stages that get the cache gate.
mkdir -p "$TMP/build/scripts" "$TMP/bin"
cp "$ROOT/scripts/build-compiler-image.sh" "$ROOT/scripts/refuse-uncached-step.sh" \
    "$TMP/build/scripts/"
printf '#!/bin/sh\n' > "$TMP/build/fetch-inputs.sh"
printf '#!/bin/sh\necho "$*" >> "$PODMAN_LOG"\n' > "$TMP/bin/podman"
chmod +x "$TMP/build/fetch-inputs.sh" "$TMP/bin/podman"
gated_stages() {
    PODMAN_LOG="$TMP/podman.log"
    : > "$PODMAN_LOG"
    PODMAN_LOG="$PODMAN_LOG" PATH="$TMP/bin:$PATH" REBUILD="$1" BUILD_JOBS=1 \
        "$TMP/build/scripts/build-compiler-image.sh" >/dev/null
    grep -F 'refuse-uncached-step.sh:/bin/sh:ro' "$PODMAN_LOG" |
        grep -o 'Dockerfile[.a-z0-9-]*' | paste -sd' ' -
}
[[ $(gated_stages all) == "" ]]
[[ $(gated_stages rust) == "Dockerfile.sdp-frida Dockerfile.tools Dockerfile.gcc16" ]]
[[ $(gated_stages none) == \
    "Dockerfile.sdp-frida Dockerfile.tools Dockerfile.gcc16 Dockerfile.rust" ]]
if gated_stages other >/dev/null 2>&1; then
    echo "build-compiler-image accepted an unknown REBUILD value" >&2
    exit 1
fi
if "$ROOT/scripts/refuse-uncached-step.sh" -c 'make all' 2>"$TMP/gate.err"; then
    echo "refuse-uncached-step permitted a step" >&2
    exit 1
fi
grep -Fq 'make all' "$TMP/gate.err"

echo "script tests passed"
