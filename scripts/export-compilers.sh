#!/usr/bin/env bash
# Copy the compiler files into a separate tree.
set -euo pipefail
out=${1:?usage: export-compilers.sh OUTPUT}
test ! -e "$out"
mkdir -p "$out/opt/rust-qnx/bin" "$out/opt/rust-qnx/lib/rustlib" "$out/opt/gcc11/bin"
cp -L /opt/rust-qnx/bin/rustc /opt/rust-qnx/bin/rustdoc /opt/rust-qnx/bin/cargo \
      /opt/rust-qnx/bin/clippy-driver /opt/rust-qnx/bin/cargo-clippy \
      /opt/rust-qnx/bin/rustfmt /opt/rust-qnx/bin/cargo-fmt "$out/opt/rust-qnx/bin/"
cp -a /opt/rust-qnx/lib/librustc_driver-*.so /opt/rust-qnx/lib/libLLVM*.so* \
    "$out/opt/rust-qnx/lib/"
for target in x86_64-unknown-linux-gnu armv7-unknown-nto-qnx650; do
    mkdir -p "$out/opt/rust-qnx/lib/rustlib/$target"
    cp -a "/opt/rust-qnx/lib/rustlib/$target/lib" "$out/opt/rust-qnx/lib/rustlib/$target/"
done
# Some old installations contain an empty LLVM placeholder.
find "$out/opt/rust-qnx/lib" -maxdepth 1 -type f -empty -delete
if [ -d /opt/rust-qnx/share ]; then
    cp -a /opt/rust-qnx/share "$out/opt/rust-qnx/"
fi

triple=arm-unknown-nto-qnx6.5.0eabi
version=11.2.0
for tool in gcc g++ cpp ar as ld nm objcopy objdump ranlib readelf size strings strip; do
    cp -L "/opt/gcc11/bin/$triple-$tool" "$out/opt/gcc11/bin/"
done
libexec="opt/gcc11/libexec/gcc/$triple/$version"
mkdir -p "$out/$libexec"
for tool in cc1 cc1plus collect2 lto1 lto-wrapper liblto_plugin.so; do
    cp -L "/$libexec/$tool" "$out/$libexec/"
done
gcclib="opt/gcc11/lib/gcc/$triple/$version"
mkdir -p "$out/$gcclib/include-fixed"
cp -a "/$gcclib/include" "$out/$gcclib/"
# Remove the local wrapper that forwards GCC headers to SDP headers.
for header in stdarg.h stddef.h; do
    file="$out/$gcclib/include/$header"
    if [ "$(sed -n '1p' "$file")" = '#ifdef __QNXNTO__' ]; then
        awk 'copy {print} /^#else$/ && !copy {copy=1}' "$file" \
            | sed '$d' > "$file.clean"
        mv "$file.clean" "$file"
    fi
done
for file in libgcc.a libgcc_eh.a; do
    cp -L "/$gcclib/$file" "$out/$gcclib/"
done
# No specs override, startup objects, sysroot, or target shared libraries.
mkdir -p "$out/usr/share/qnx-compiler"
find "$out/opt" -type f -print0 | sort -z | xargs -0 sha256sum \
    | sed "s|  $out/|  /|" > "$out/usr/share/qnx-compiler/FILES.sha256"
{
    /opt/rust-qnx/bin/rustc -vV
    /opt/rust-qnx/bin/cargo -V
    /opt/gcc11/bin/arm-unknown-nto-qnx6.5.0eabi-gcc -v 2>&1
} > "$out/usr/share/qnx-compiler/VERSIONS.txt"
