# Source inputs and verification

This repository contains compiler build recipes. The final compiler image
contains no QNX SDP tree or QNX runtime implementation. Separate intermediate
images contain the SDP files used to assemble the toolchains.

`sources.manifest` records direct input URLs, archive hashes, Git revisions,
and image digests. The source checks compare these pins with the recipes.
The complete compiler build uses the pinned Frida image as its SDP input.
Do not upload the intermediate images or their caches.

The pinned Rust checkout records the stage-0 compiler, LLVM submodule, Cargo
lock files, and dependency checksums. Rust bootstrap verifies its downloads.
The recipe also verifies the backtrace submodule revision before applying
its patch. A Rust revision change requires a review of these inputs.

The compiler release contains the GNU source archives, patches, build
recipes, Rust source revisions, patch hashes, and license notices.
It also contains the exact Ubuntu source packages for its installed host
programs. Those files have their own package inventory and hash manifest.

APT uses live Ubuntu repositories. The base image has a digest pin, but
package versions can change. The build is not bit-for-bit reproducible.
The package inventory records the inputs of each final image.

The runner is a separate local image. Its GitHub runner archive has a version
and SHA-256 pin. Its Ubuntu base has a digest pin. Runner state and build
storage remain private and separate from the compiler release.
