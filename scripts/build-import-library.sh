#!/usr/bin/env bash
# Assemble a link-only library from interface declarations.
set -euo pipefail
if [ "$#" -ne 3 ]; then
    echo 'usage: build-import-library.sh SONAME SYMBOLS OUTPUT' >&2
    exit 2
fi
soname=$1
symbols=$2
output=$3
[[ $soname =~ ^lib[A-Za-z0-9_]+\.so\.[0-9]+$ ]] || exit 2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '.syntax unified\n.arm\n' > "$work/imports.s"
count=0
declare -A versions=()
while read -r kind size name extra; do
    [ -n "$kind" ] || continue
    version=
    marker=@
    public_name=$name
    if [[ $name == *@* ]]; then
        [[ $name == *@@* ]] && marker=@@
        public_name=${name%%@*}
        version=${name##*@}
        [[ $version =~ ^lib[A-Za-z0-9_]+\.so\.[0-9]+$ ]] || exit 2
        versions[$version]=1
        name=qnx_import_$count
    fi
    [[ -z $extra && $size =~ ^[0-9]+$ && $public_name =~ ^[A-Za-z_][A-Za-z_0-9]*$ ]] || {
        echo 'Invalid symbol declaration' >&2
        exit 2
    }
    case "$kind" in
        FUNC) section=.text; type='%function'; size=4 ;;
        OBJECT) section=.data; type='%object' ;;
        *) echo 'Invalid symbol type' >&2; exit 2 ;;
    esac
    printf '%s\n.balign 4\n.global %s\n.type %s,%s\n%s:\n.space %s\n.size %s,%s\n' \
        "$section" "$name" "$name" "$type" "$name" "$size" "$name" "$size" >> "$work/imports.s"
    if [ -n "$version" ]; then
        printf '.symver %s,%s%s%s,remove\n' "$name" "$public_name" "$marker" "$version" >> "$work/imports.s"
    fi
    count=$((count + 1))
done < "$symbols"
[ "$count" -gt 0 ]
arm-unknown-nto-qnx6.5.0eabi-as -march=armv7-a -meabi=5 -o "$work/imports.o" "$work/imports.s"
ld_args=()
if [ "${#versions[@]}" -gt 0 ]; then
    for version in "${!versions[@]}"; do
        printf '%s { };\n' "$version"
    done | sort > "$work/versions.map"
    ld_args+=(--version-script="$work/versions.map")
fi
arm-unknown-nto-qnx6.5.0eabi-ld -shared --soname="$soname" "${ld_args[@]}" -o "$output" "$work/imports.o"
# These libraries contain no runtime implementation. Do not deploy them.
