# QNX 6.5 ARM Rust compiler image

This repository assembles a compiler image for ARM Rust archives and shared
libraries that run on QNX 6.5. The final image contains Rust, Cargo, GNU
compilers, binutils, source archives, and license notices.

The final image contains no QNX SDP tree, QNX runtime implementation, or
activation record. It contains target definitions and runtime interface
declarations. This independent project has no affiliation with QNX.

## Assemble the image

Use Linux on x86-64 with Podman. Provide at least 50 GiB of free build storage
and 16 GiB of RAM. The storage figure is a build allowance, not a measured
minimum.

```sh
scripts/build-compiler-image.sh
```

The command creates `localhost/qnx650-compiler:source` and runs its tests.
It uses one job per CPU for the Rust build by default. Set `BUILD_JOBS` to
change this value.

The complete build uses the pinned Frida QNX tools image as an intermediate
input. That input contains SDP files. The intermediate images and their
caches stay local. Only the final compiler image is an upload candidate.
The supporting SDP recipes remain in this repository as build inputs.

## Build a Rust library

```sh
podman run --rm -v "$PWD:/src" -w /src \
  localhost/qnx650-compiler:source \
  cargo build --lib --release --locked --target armv7-unknown-nto-qnx650
```

Projects with native glue must also compile and link that glue.
The linker accepts only declared runtime imports.
The QNX device supplies the actual runtime libraries when it loads the output.
Do not deploy the generated libraries from `/opt/qnx-link-only`.

Executables link with the image's own startup object. The image does not
supply general QNX C/C++ headers. It supports the documented archive,
shared-library and executable build paths.

## Publish the public image

The GitHub `compiler image` workflow runs on a runner with the
`qnx650-compiler` label by default. The workflow runs only on the default
branch and starts only through manual dispatch.

Set `publish` to `true` to upload the checked final image to GHCR.
GitHub creates a new package with private visibility. After the first upload,
set its visibility to Public in the package settings. Run the `public image
check` workflow with the printed digest. Consumers can then use that digest
without registry credentials.

[Local runner setup](runner/README.md) describes the separate runner container.

[Compiler image details](docs/COMPILER-IMAGE.md) describe the build stages,
link inputs, package access, and source notices.

## Verify the source

Install Bash, Git, Python 3, ripgrep, jq, and ShellCheck. Run:

```sh
scripts/check-release-readiness.sh
sha256sum --check SOURCE-FILES.sha256
```

Original files use the Apache-2.0 license. Upstream patches keep their upstream
licenses. [Third-party notices](THIRD_PARTY_NOTICES.md) identify those inputs.
