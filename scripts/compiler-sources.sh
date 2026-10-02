#!/usr/bin/env bash
# Keep the GNU source archives beside the compiler distribution.
set -euo pipefail
out=${1:?usage: compiler-sources.sh OUTPUT}
mkdir -p "$out"
while IFS='|' read -r name _kind path hash url _mirror; do
    name=${name//[[:space:]]/}
    case "$name" in binutils-2.42|gcc-qnx-a07570b6) ;; *) continue ;; esac
    path=${path//[[:space:]]/}
    hash=${hash//[[:space:]]/}
    url=${url//[[:space:]]/}
    curl --fail --location --retry 3 --output "$out/$path" "$url"
    printf '%s  %s\n' "$hash" "$out/$path" | sha256sum --check -
done < sources.manifest
cp -a patches toolchain-fixups gcc11-fixups LICENSES "$out/"
mkdir -p "$out/scripts"
cp scripts/export-compilers.sh scripts/compiler-sources.sh "$out/scripts/"
cp build-toolchain.sh Dockerfile Dockerfile.sdp-frida Dockerfile.tools \
    LICENSE sources.manifest "$out/"
# Recipe comments are not source inputs. Remove private build notes.
for recipe in sources.manifest Dockerfile Dockerfile.sdp-frida Dockerfile.tools; do
    awk '!/^[[:space:]]*#/' "$out/$recipe" > "$out/$recipe.clean"
    mv "$out/$recipe.clean" "$out/$recipe"
done
