#!/usr/bin/env bash
# Link a shared library without a QNX sysroot.
set -euo pipefail
: "${QNX_IMPORT_LIBRARY_DIR:?Set QNX_IMPORT_LIBRARY_DIR to the link-only library directory}"
shared=0
args=()
for arg do
    case "$arg" in
        -shared) shared=1; args+=("$arg") ;;
        -lgcc_s|-lgcc_eh) args+=(-lgcc) ;;
        -static-libgcc) ;;
        *) args+=("$arg") ;;
    esac
done
if [ "$shared" -ne 1 ]; then
    echo 'This linker supports shared libraries only.' >&2
    exit 2
fi
exidx=${QNX_EXIDX_SCRIPT:-/usr/share/qnx-compiler/exidx-merge.ld}
exec arm-unknown-nto-qnx6.5.0eabi-gcc -nostdlib \
    -Wl,--no-undefined -Wl,-z,noexecstack -Wl,-T,"$exidx" -L"$QNX_IMPORT_LIBRARY_DIR" \
    "${args[@]}"
