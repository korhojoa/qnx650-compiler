# Third-party notices

This repository contains patches against third-party projects. A patch remains
a modification of its upstream work and is offered under the terms applicable
to that work. The project-level licence does not replace those terms.

Repository-original scripts, tests, and documentation are licensed under the
Apache License 2.0 in `LICENSE`, except where a file states otherwise.

| Repository paths | Upstream and pinned revision | Licence | Bundled text |
|---|---|---|---|
| `patches/*.patch`, `gcc16-port/gcc16-qnx650.patch` | GCC (`a07570b654eb6e70adaf5af813b73799d94c9df8` and GCC 16.1.0) | GPL-3.0-or-later; GCC Runtime Library Exception applies where stated upstream | `LICENSES/GPL-3.0.txt`, `LICENSES/GCC-Runtime-Library-Exception-3.1.txt` |
| `rust-port/rust-qnx650.patch` | Rust (`b940084d7eb6a299eb4bfeb8e34901bc051e7ac4`) | Apache-2.0 OR MIT | `LICENSE`, `LICENSES/Rust-MIT.txt` |
| `compiler-notices/copyright-path-deps.patch` | Rust (`b940084d7eb6a299eb4bfeb8e34901bc051e7ac4`) | Apache-2.0 OR MIT | `LICENSE`, `LICENSES/Rust-MIT.txt` |
| `rust-port/libc-qnx650.patch` | rust-lang/libc (`ef0906e20828777175f65caa7e681a0ce33c559a`) | Apache-2.0 OR MIT | `LICENSE`, `LICENSES/libc-MIT.txt` |
| `rust-port/cc-qnx650.patch` | rust-lang/cc-rs (`3c4ab883616b373c0287319d1a2f237aad0c79a0`) | Apache-2.0 OR MIT | `LICENSE`, `LICENSES/cc-rs-MIT.txt` |
| `rust-port/backtrace-qnx650.patch` | rust-lang/backtrace (`d902726a1dcdc1e1c66f73d1162181b5423c645b`) | Apache-2.0 OR MIT | `LICENSE`, `LICENSES/backtrace-MIT.txt` |

The exact source URLs and cryptographic revisions are recorded in
`sources.manifest`. Copyright notices embedded in patch context and added files
remain in force.

The compiler image carries its own notices for the Rust, LLVM, Cargo, GNU and
Ubuntu components that it contains. [Compiler image details](docs/COMPILER-IMAGE.md)
give their locations in the image.

No QNX software is included or licensed by this repository. QNX SDP media,
licence material, installed files, and images containing them must be obtained
and handled separately by each user under their applicable QNX terms.

The bundled texts were copied from the pinned upstream checkouts. Verify this
table against the exact staged snapshot before each release.
