#!/usr/bin/env bash
# Link an executable without a QNX sysroot: the image's startup object, the
# link-only runtime libraries and the ARM exception-index merge script.
set -euo pipefail
: "${QNX_IMPORT_LIBRARY_DIR:?Set QNX_IMPORT_LIBRARY_DIR to the link-only library directory}"
args=()
for arg do
    case "$arg" in
        -shared) echo 'This linker supports executables only.' >&2; exit 2 ;;
        -lgcc_s|-lgcc_eh) args+=(-lgcc) ;;
        -static-libgcc) ;;
        *) args+=("$arg") ;;
    esac
done
exidx=${QNX_EXIDX_SCRIPT:-/usr/share/qnx-compiler/exidx-merge.ld}
start=${QNX_START_OBJECT:-/usr/share/qnx-compiler/qnx-start.o}
# An executable always fails on an undefined symbol; the driver's own spec
# names the program interpreter.
exec arm-unknown-nto-qnx6.5.0eabi-gcc -nostdlib \
    -Wl,-z,noexecstack -Wl,-T,"$exidx" -L"$QNX_IMPORT_LIBRARY_DIR" \
    "$start" "${args[@]}" -lgcc
