#!/usr/bin/env bash
# Upload only the checked compiler image.
set -euo pipefail
: "${GH_TOKEN:?}"
: "${REGISTRY_OWNER:?}"
: "${REGISTRY_ACTOR:?}"
: "${SOURCE_REVISION:?}"
[[ $REGISTRY_OWNER =~ ^[A-Za-z0-9-]+$ ]] || exit 2
[[ $REGISTRY_ACTOR =~ ^[A-Za-z0-9_-]+(\[bot\])?$ ]] || exit 2
[[ $SOURCE_REVISION =~ ^[0-9a-f]{40}$ ]] || exit 2
owner=${REGISTRY_OWNER,,}
package=qnx650-compiler
image=${COMPILER_IMAGE:-localhost/qnx650-compiler:source}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Repeat the image tests before upload.
root=$(cd "$(dirname "$0")/.." && pwd)
podman run --rm --network none --read-only --tmpfs /tmp \
    -v "$root:/recipe:ro" "$image" /recipe/tests/check-compiler-image.sh
podman run --rm --network none "$image" test -s /opt/rust-qnx/share/doc/rust/SOURCES.txt
podman run --rm --network none "$image" sh -c \
    'test -s /opt/rust-qnx/share/doc/rust/PATCHES.sha256 && test -s /usr/share/qnx-compiler/source/gcc-qnx.tar.gz && cmp /usr/share/qnx-compiler/HOST-PACKAGES.txt /usr/share/qnx-compiler/ubuntu-source/PACKAGES.txt'
remote="ghcr.io/$owner/$package:sha-$SOURCE_REVISION"
printf '%s' "$GH_TOKEN" | podman login --authfile "$work/auth.json" \
    --username "$REGISTRY_ACTOR" --password-stdin ghcr.io
podman push --authfile "$work/auth.json" --digestfile "$work/digest" "$image" "docker://$remote"
printf 'Image: ghcr.io/%s/%s@%s\n' "$owner" "$package" "$(cat "$work/digest")"

# A new GHCR package requires a visibility change in its settings.
reference="ghcr.io/$owner/$package@$(cat "$work/digest")"
if ! "$root/scripts/check-public-image.sh" "$reference"; then
    echo "The upload completed, but public access is not verified." >&2
    echo "Set package visibility to Public in GitHub package settings." >&2
    echo "Run the public image check workflow with the printed digest." >&2
    exit 3
fi
