# Source and compiler verification

The selected source passes these checks:

- Shell syntax and ShellCheck.
- Source pins and Dockerfile input checks.
- Script fixture tests.
- Ruff check, Ruff format, and ty for the Python helpers.
- ASCII and private-reference checks.
- Actionlint for the two GitHub workflows.
- The source hash manifest.

The compiler-image tests pass with the audited local release image.
They compile and link an ARM shared library with allocation and panic
unwinding. They reject an unknown runtime import. They also compile and run
a Linux Cargo build script.

The Python GNU helpers also pass their compiler and linker checks in a
separate disposable toolchain container.

These checks do not constitute a new complete source build of this repository.
The manual GitHub workflow must verify the complete build before the first
image publication. The source checks do not require QNX media or credentials.

## Local runner checks

The runner image passes these local checks:

- The GitHub runner starts and reports version 2.337.0.
- Nested Podman uses overlay storage with fuse-overlayfs.
- A nested image build executes a build command.
- A container from that image returns the expected test output.
- `nproc` returns the configured CPU count.

The runner is not registered with GitHub. These local checks do not verify
a GitHub connection or a complete compiler workflow run.

## Publication checks

Local command fixtures verify these publication paths:

- A public manifest has the expected SHA-256 digest.
- Denied anonymous access fails the public check.
- A different manifest digest fails the public check.
- The publisher reports a completed upload with unverified public access.
- A failed image check prevents registry login and upload.
- A failed registry push returns an error.
- Anonymous requests contain no upload credential.

These tests use command fixtures. No actual image upload or anonymous access
to a new compiler package has been verified.
