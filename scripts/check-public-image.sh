#!/usr/bin/env bash
# Verify registry access to the exact image without account credentials.
set -euo pipefail
reference=${1:?usage: check-public-image.sh GHCR_IMAGE_DIGEST}
[[ $reference =~ ^ghcr\.io/([a-z0-9-]+)/qnx650-compiler@(sha256:[0-9a-f]{64})$ ]] || {
    echo 'Use the GHCR compiler image reference with its SHA-256 digest.' >&2
    exit 2
}
repository="${BASH_REMATCH[1]}/qnx650-compiler"
digest=${BASH_REMATCH[2]}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# This request uses no GitHub token or registry login.
curl -q --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    --get --data-urlencode 'service=ghcr.io' \
    --data-urlencode "scope=repository:$repository:pull" \
    https://ghcr.io/token > "$work/token.json"
token=$(jq -er '.token // .access_token' "$work/token.json")
curl -q --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    --header "Authorization: Bearer $token" \
    --header 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://ghcr.io/v2/$repository/manifests/$digest" > "$work/manifest.json"
printf '%s  %s\n' "${digest#sha256:}" "$work/manifest.json" | sha256sum --check --status -
echo "Public image manifest verified: $reference"
