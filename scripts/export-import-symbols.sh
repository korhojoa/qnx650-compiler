#!/usr/bin/env bash
# Write the link-only symbol declarations from the QNX runtime libraries.
# Run it inside a local image that contains the SDP target tree. It reads
# the export tables of libc.so.3, libm.so.2 and libsocket.so.3 and writes
# one declaration per line to compiler-imports/: KIND SIZE NAME[@VERSION].
# The output contains names, sizes and version tags only, no code or data.
set -euo pipefail
out=${1:?usage: export-import-symbols.sh OUTPUT_DIR [LIB_DIR]}
libdir=${2:-/opt/qnx650/target/qnx6/armle-v7/lib}
# The declared libraries. Keep this list equal to the loop in Dockerfile.compiler.
libs=${QNX_IMPORT_LIBS:-libc.so.3 libm.so.2 libsocket.so.3 libusbdi.so.2 libpps.so.1 libasound.so.2 libz.so.2}
mkdir -p "$out"
for lib in $libs; do
    # The SDP keeps the core libraries in lib/ and the others in usr/lib/.
    file=$libdir/$lib
    [ -f "$file" ] || file=$libdir/../usr/lib/$lib
    [ -f "$file" ] || { echo "missing $lib under $libdir" >&2; exit 1; }
    # Columns: Num Value Size Type Bind Vis Ndx Name. A versioned name is
    # printed as name@VER or name@@VER. Keep defined, visible, global or weak
    # functions and objects whose names the assembler accepts.
    readelf --dyn-syms -W "$file" | awk '
        $1 ~ /^[0-9]+:$/ && $7 != "UND" \
            && ($4 == "FUNC" || $4 == "OBJECT") \
            && ($5 == "GLOBAL" || $5 == "WEAK") \
            && ($6 == "DEFAULT" || $6 == "PROTECTED") {
            name = $8
            base = name
            sub(/@.*/, "", base)
            if (base !~ /^[A-Za-z_][A-Za-z_0-9]*$/) {
                print "skipped (name): " name > "/dev/stderr"
                next
            }
            size = ($4 == "FUNC") ? 4 : $3
            print $4, size, name
        }' | sort -u -k3,3 -k1,1 > "$out/$lib.symbols"
    printf '%s: %s declarations\n' "$lib" "$(wc -l < "$out/$lib.symbols")"
done
