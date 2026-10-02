# Compiler image

The compiler image supports ARM Rust archives and shared libraries for QNX 6.5.
It contains Rust, Cargo, an ARM GNU compiler, and GNU binutils.
The final image starts from Ubuntu. It contains no QNX SDP tree or activation record.

The build uses the existing source recipes in separate stages.
Those stages can contain SDK files. The final image copies only the compiler file list.
The workflow uploads only the final image. It does not upload the build stages or their cache.

## Local build

Run the source build:

```sh
scripts/build-compiler-image.sh
```

The build creates `localhost/qnx650-compiler:source`.
The build also runs the compiler image tests.
The tests compile a Rust shared library with allocation and panic unwinding.
An unknown runtime import causes a link failure.

The optional `COMPILER_BUILD_BASE` variable selects an existing GNU build image.
This variable permits reuse of local build inputs.
The GitHub workflow uses the complete source build.

## Native dependencies

The image contains link-only declarations for `libc.so.3`, `libm.so.2`, and `libsocket.so.3`.
The assembler creates these declarations from the text files in `compiler-imports/`.
They contain symbol names and ELF metadata. They contain no QNX runtime implementation.
The resulting application uses the actual libraries on the QNX device.

Do not copy `/opt/qnx-link-only` to a QNX device.
Its files are link inputs only.

The shared linker rejects unknown imports. It also merges the ARM exception-index sections.
Cargo uses this linker for `armv7-unknown-nto-qnx650` shared libraries.
The image does not supply executable startup objects or general QNX C/C++ headers.
The small `stdio.h` declares only `vsnprintf` for existing variadic logging glue.

For a separate GNU link, use these inputs:

```sh
arm-unknown-nto-qnx6.5.0eabi-gcc \
  -nostdlib -shared -fPIC -mno-unaligned-access \
  -Wl,--no-undefined -Wl,-z,noexecstack \
  -Wl,-T,/usr/share/qnx-compiler/exidx-merge.ld \
  -L/opt/qnx-link-only \
  -o output.so input.o input.a -lgcc -lc -lm -lsocket
```

## Public GHCR publication

The workflow requires 50 GiB of free build storage before the source build.
The local source build and a GitHub workflow run are separate tests.

1. Open the `compiler image` workflow in GitHub Actions.
2. Select the default branch.
3. Select the `qnx650-compiler` runner label.
4. Set `publish` to `true` and run the workflow.
5. Inspect the compiler build and test results.
6. Record the printed image digest.
7. After the first upload, set the package visibility to Public.
8. Run the `public image check` workflow with the printed digest.
9. Use that digest in each consumer pipeline.

Set `publish` to `false` for a build check without an upload.
The image name is `ghcr.io/<owner>/qnx650-compiler:sha-<commit>`.
The upload workflow uses `GITHUB_TOKEN` with package write access.

GitHub creates a new package with private visibility. The upload script
checks anonymous access after the transfer. If access fails, the upload
remains complete but the script returns an error. Change the package
visibility, then run the separate public check without a new build.
Later uploads to the public package can pass the check in the upload job.

The check uses an anonymous registry token. It downloads the exact manifest
and verifies its SHA-256 digest. It does not use account credentials or
transfer all image layers.

The [GitHub package documentation](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)
describes package visibility. The
[container documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
describes public access and upload authentication.

A consumer can use this job without registry credentials:

```yaml
permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-24.04
    container:
      image: ghcr.io/OWNER/qnx650-compiler@sha256:DIGEST
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
        with:
          persist-credentials: false
      - run: cargo build --lib --release --locked --target armv7-unknown-nto-qnx650
```

Replace `OWNER` and `DIGEST` with the package owner and verified digest.
Projects with native glue must also run their GNU link step.

## Source and notices

The release stage requires the Rust, LLVM, and Cargo license notices.
It also includes the verified GNU source archives, patches, and build recipes.
The source files are in `/usr/share/qnx-compiler/source`.
Rust source revisions are in `/opt/rust-qnx/share/doc/rust/SOURCES.txt`.
The applied patch hashes are in the adjacent `PATCHES.sha256` file.
Ubuntu package notices remain in `/usr/share/doc`.
The exact Ubuntu source packages are in `/usr/share/qnx-compiler/ubuntu-source`.
That directory contains the package versions and source-file hashes.

The `compiler` stage permits local build tests with an older toolchain.
The `compiler-release` stage requires the distribution notices.
Only the release stage is an input to the publication workflow.
