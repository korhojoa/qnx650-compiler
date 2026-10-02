#!/usr/bin/env bash
# Run this test inside the compiler image.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
test ! -e /opt/qnx650
test ! -e /etc/qnx
sha256sum --quiet --check /usr/share/qnx-compiler/FILES.sha256
rustc -vV
cargo -V
rustc "$root/tests/compiler-probe.rs" --edition 2024 --crate-type cdylib \
    --target armv7-unknown-nto-qnx650 -C panic=unwind -C opt-level=2 \
    -C linker=/usr/local/bin/link-qnx-shared.sh -o "$work/probe.so"
readelf -h -l -d -SW "$work/probe.so" > "$work/elf.txt"
grep 'Version5 EABI' "$work/elf.txt"
grep 'ARM_EXIDX' "$work/elf.txt"
grep NEEDED "$work/elf.txt"
if grep NEEDED "$work/elf.txt" | grep -vE 'libc.so.3|libm.so.2|libsocket.so.3'; then
    echo 'Unexpected native dependency' >&2
    exit 1
fi
if grep -q TEXTREL "$work/elf.txt"; then
    echo 'Text relocation detected' >&2
    exit 1
fi
# An unknown runtime import must fail the link.
cat > "$work/missing.rs" <<'EOF'
unsafe extern "C" { fn missing_qnx_runtime_import() -> u32; }
#[unsafe(no_mangle)]
pub extern "C" fn missing_probe() -> u32 { unsafe { missing_qnx_runtime_import() } }
EOF
if rustc "$work/missing.rs" --edition 2024 --crate-type cdylib \
    --target armv7-unknown-nto-qnx650 -C panic=abort \
    -C linker=/usr/local/bin/link-qnx-shared.sh -o "$work/missing.so" > "$work/missing.log" 2>&1; then
    echo 'The linker accepted an unknown runtime import' >&2
    exit 1
fi
grep 'undefined reference.*missing_qnx_runtime_import' "$work/missing.log"
# A plugin library may leave symbols for its host process when asked.
QNX_LINK_UNDEFINED=allow rustc "$work/missing.rs" --edition 2024 --crate-type cdylib \
    --target armv7-unknown-nto-qnx650 -C panic=abort \
    -C linker=/usr/local/bin/link-qnx-shared.sh -o "$work/plugin.so"
readelf --dyn-syms -W "$work/plugin.so" | grep -q ' UND .*missing_qnx_runtime_import'
# The other declared libraries link by name.
for lib in usbdi pps asound z; do
    test -e "/opt/qnx-link-only/lib$lib.so"
done
# An executable links with the image's startup object through the Cargo
# linker: entry at _start, the QNX program interpreter, no undefined symbol.
cat > "$work/hello.rs" <<'EOF'
fn main() {
    let args: Vec<String> = std::env::args().collect();
    println!("hello from {}", args.first().map(String::as_str).unwrap_or("?"));
}
EOF
rustc "$work/hello.rs" --edition 2024 --crate-type bin \
    --target armv7-unknown-nto-qnx650 -C opt-level=2 \
    -C linker=/usr/local/bin/link-qnx.sh -o "$work/hello"
readelf -h -l -d -s -W "$work/hello" > "$work/hello.txt"
grep -q 'Version5 EABI' "$work/hello.txt"
grep -q 'Requesting program interpreter: /usr/lib/ldqnx.so.2' "$work/hello.txt"
entry=$(awk '/Entry point address/ {print $4}' "$work/hello.txt")
start=$(awk '$8 == "_start" {print "0x" $2}' "$work/hello.txt" | head -1)
[ "$((entry))" -eq "$((start))" ]
grep -q 'ARM_EXIDX' "$work/hello.txt"
if grep NEEDED "$work/hello.txt" | grep -vE 'libc.so.3|libm.so.2|libsocket.so.3'; then
    echo 'Unexpected native dependency in the executable' >&2
    exit 1
fi
# Cargo build scripts must use the Linux host compiler.
mkdir -p "$work/host/src"
printf '[package]\nname="compiler-host-check"\nversion="0.1.0"\nedition="2024"\n' > "$work/host/Cargo.toml"
printf 'fn main() {}\n' > "$work/host/build.rs"
printf 'fn main() {}\n' > "$work/host/src/main.rs"
CARGO_HOME="$work/cargo-home" cargo build --offline --manifest-path "$work/host/Cargo.toml"
"$work/host/target/debug/compiler-host-check"
echo 'Compiler image checks passed'
