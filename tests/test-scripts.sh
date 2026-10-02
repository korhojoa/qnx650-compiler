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

echo "script tests passed"
