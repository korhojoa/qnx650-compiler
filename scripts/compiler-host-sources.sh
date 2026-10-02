#!/usr/bin/env bash
# Keep the exact Ubuntu source packages with the host programs.
set -euo pipefail
out=${1:?usage: compiler-host-sources.sh OUTPUT PACKAGES}
packages=${2:?usage: compiler-host-sources.sh OUTPUT PACKAGES}
mkdir -p "$out"
cp "$packages" "$out/PACKAGES.txt"
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
apt-get update
cd "$out"
while read -r package version; do
    apt-get source --download-only --only-source "$package=$version"
done < PACKAGES.txt
# The hash output file is excluded from the input list.
# shellcheck disable=SC2094
find . -maxdepth 1 -type f ! -name FILES.sha256 -print0 | sort -z \
    | xargs -0 sha256sum > FILES.sha256
