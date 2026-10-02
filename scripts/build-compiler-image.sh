#!/usr/bin/env bash
# Assemble the compiler image from the source recipes.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
prefix=${COMPILER_BUILD_PREFIX:-localhost/qnx650-compiler-build}
image=${COMPILER_IMAGE:-localhost/qnx650-compiler:source}
jobs=${BUILD_JOBS:-$(nproc)}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || exit 2
command -v podman >/dev/null
if [ -z "${COMPILER_BUILD_BASE:-}" ]; then
    ./fetch-inputs.sh
    podman build -f Dockerfile.sdp-frida -t "$prefix:base" .
    podman build -f Dockerfile.tools --build-arg BASE="$prefix:base" -t "$prefix:tools" .
    podman build -f Dockerfile.gcc16 --build-arg BASE="$prefix:tools" \
        --build-arg QNX_TARGETS=arm -t "$prefix:gcc16" .
    base="$prefix:gcc16"
else
    base=$COMPILER_BUILD_BASE
fi
podman build -f Dockerfile.rust --build-arg BASE="$base" \
    --build-arg QNX_TARGETS=arm --build-arg BUILD_JOBS="$jobs" -t "$prefix:rust" .
podman build -f Dockerfile.compiler --target compiler-release \
    --build-arg TOOLCHAIN_IMAGE="$prefix:rust" -t "$image" .
podman run --rm --network none --read-only --tmpfs /tmp \
    -v "$root:/recipe:ro" "$image" /recipe/tests/check-compiler-image.sh
echo "Compiler image: $image"
