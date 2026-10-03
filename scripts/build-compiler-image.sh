#!/usr/bin/env bash
# Assemble the compiler image from the source recipes.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
prefix=${COMPILER_BUILD_PREFIX:-localhost/qnx650-compiler-build}
image=${COMPILER_IMAGE:-localhost/qnx650-compiler:source}
jobs=${BUILD_JOBS:-$(nproc)}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || exit 2
# REBUILD gives the stages that can build without the layer cache:
# all, rust (not the GNU stages), or none (only the final image).
# A mounted volume is not a part of the cache key of a step.
rebuild=${REBUILD:-all}
gate=(-v "$root/scripts/refuse-uncached-step.sh:/bin/sh:ro")
gnu_gate=()
rust_gate=()
case $rebuild in
    all) ;;
    rust) gnu_gate=("${gate[@]}") ;;
    none) gnu_gate=("${gate[@]}") rust_gate=("${gate[@]}") ;;
    *) echo "REBUILD must be all, rust or none." >&2; exit 2 ;;
esac
command -v podman >/dev/null
./fetch-inputs.sh
if [ -z "${COMPILER_BUILD_BASE:-}" ]; then
    podman build "${gnu_gate[@]}" -f Dockerfile.sdp-frida -t "$prefix:base" .
    podman build "${gnu_gate[@]}" -f Dockerfile.tools \
        --build-arg BASE="$prefix:base" -t "$prefix:tools" .
    podman build "${gnu_gate[@]}" -f Dockerfile.gcc16 \
        --build-arg BASE="$prefix:tools" \
        --build-arg QNX_TARGETS=arm -t "$prefix:gcc16" .
    base="$prefix:gcc16"
else
    base=$COMPILER_BUILD_BASE
fi
podman build "${rust_gate[@]}" -f Dockerfile.rust --build-arg BASE="$base" \
    --build-arg QNX_TARGETS=arm --build-arg BUILD_JOBS="$jobs" -t "$prefix:rust" .
podman build -f Dockerfile.compiler --target compiler-release \
    --build-arg TOOLCHAIN_IMAGE="$prefix:rust" -t "$image" .
podman run --rm --network none --read-only --tmpfs /tmp \
    -v "$root:/recipe:ro" "$image" /recipe/tests/check-compiler-image.sh
echo "Compiler image: $image"
