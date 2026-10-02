#!/bin/bash
# Build binutils 2.42 + GCC 11.2 cross-toolchains for QNX Neutrino 6.5.0
# (C and C++), installed to /opt/gcc11. Runs in the gcc-builder stage of the
# Dockerfile against the SDP's target tree as sysroot.
#
# Targets:
#   arm-unknown-nto-qnx6.5.0eabi  (armle-v7: armv7-a, softfp, vfpv3)
#   i386-pc-nto-qnx6.5.0
# The SDP's own 4.4-era tools use arm-unknown-nto-qnx6.5.0-* (no "eabi") and
# i486-pc-*, so nothing collides on PATH.
#
# GCC source is the QNX community port (mainline GCC has no arm-nto target),
# via https://github.com/bigunclemax/gcc branch qnx_11_2, pinned by commit.
# patches/0001..0004 fix QNX-6.5-specific breakage; see each patch header.
set -euo pipefail

# Overridable so a patched toolchain can be built to a SIDE prefix and tested
# without disturbing the working /opt/gcc11 (the path is baked in at configure
# time, so whatever is chosen here is where the result must be mounted to run).
PREFIX=${PREFIX:-/opt/gcc11}
SYSROOT=/opt/qnx650/target/qnx6
WORK=${WORK:-/tmp/toolchain}
PATCHES=${PATCHES:-/patches}
BINUTILS_VERSION=2.42
GCC_COMMIT=a07570b654eb6e70adaf5af813b73799d94c9df8   # head of qnx_11_2, 2022-07-13
JOBS=$(nproc)
export PATH="$PREFIX/bin:$PATH"

ARM_TARGET=arm-unknown-nto-qnx6.5.0eabi
X86_TARGET=i386-pc-nto-qnx6.5.0

sources() {
    mkdir -p $WORK && cd $WORK
    wget -nv https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz
    wget -nv -O gcc-qnx.tar.gz \
        https://github.com/bigunclemax/gcc/archive/$GCC_COMMIT.tar.gz
    # Verify before compiling -- both were previously trusted outright.
    # INLINE rather than calling verify-sha.sh, because the Dockerfile does
    # "COPY build-toolchain.sh /" and runs it at / with only /patches beside
    # it: no helper and no manifest exist inside the image build. These hashes
    # are duplicated in sources.manifest -- change BINUTILS_VERSION or
    # GCC_COMMIT and BOTH must be updated.
    echo "f6e4d41fd5fc778b06b7891457b3620da5ecea1006c6a4a41ae998109f85a800  binutils-$BINUTILS_VERSION.tar.xz" | sha256sum -c -
    echo "130014580b52f292df5958461ccea39d7aa9d3f9e02a7f13a309e9ada6302518  gcc-qnx.tar.gz" | sha256sum -c -
    tar xf binutils-$BINUTILS_VERSION.tar.xz
    mkdir gcc-qnx && tar xf gcc-qnx.tar.gz --strip-components=1 -C gcc-qnx
    cd gcc-qnx
    for p in $PATCHES/*.patch; do patch -p1 < "$p"; done
}

# The fork's arm/nto-eabi.h searches the sysroot's plain lib/ and usr/lib/
# (no multilib os-dir mapping, unlike i386/nto.h which appends a "/x86"
# sysroot suffix itself). Give ARM a symlink view of the QNX target tree
# with armle-v7 as the default CPU. The same links must exist in any image
# that runs the toolchain -- the path is baked in at configure time.
sysroot_arm() {
    mkdir -p $SYSROOT-armle-v7/usr
    ln -sfn ../qnx6/armle-v7/lib        $SYSROOT-armle-v7/lib
    ln -sfn ../../qnx6/usr/include      $SYSROOT-armle-v7/usr/include
    ln -sfn ../../qnx6/armle-v7/usr/lib $SYSROOT-armle-v7/usr/lib
}

binutils() { # $1 = target
    local target=$1
    mkdir -p $WORK/build/binutils-$target
    cd $WORK/build/binutils-$target
    $WORK/binutils-$BINUTILS_VERSION/configure \
        --target=$target \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
        --disable-nls \
        --enable-lto
    make -j$JOBS
    make install-strip
}

gcc_build() { # $1 = target, $2 = sysroot, extra args = arch flags
    local target=$1 sysroot=$2; shift 2
    local target_cflags="-g -O2" target_cxxflags="-g -O2"
    if [ "$target" = "$ARM_TARGET" ]; then
        # The supported ARM systems may trap unaligned accesses. These flags
        # must cover the compiler runtime and target libraries themselves;
        # application flags cannot repair code embedded in static archives.
        target_cflags="$target_cflags -mno-unaligned-access"
        target_cxxflags="$target_cxxflags -mno-unaligned-access"
    fi
    mkdir -p $WORK/build/gcc-$target
    cd $WORK/build/gcc-$target
    $WORK/gcc-qnx/configure \
        --target=$target \
        --prefix=$PREFIX \
        --with-sysroot=$sysroot \
        --with-as=$PREFIX/bin/$target-as \
        --with-ld=$PREFIX/bin/$target-ld \
        --enable-languages=c,c++ \
        --with-default-libstdcxx-abi=gcc4-compatible \
        --enable-gnu-indirect-function=no \
        --with-system-zlib \
        --enable-threads=posix \
        --enable-__cxa_atexit \
        --enable-shared \
        --enable-static \
        --enable-libgomp \
        --disable-werror \
        --disable-nls \
        --disable-tls \
        --disable-libssp \
        --disable-libstdcxx-pch \
        --disable-libsanitizer \
        --disable-bootstrap \
        "$@"
    # Build the compiler first, then drop fixincludes' auto-edited copies of
    # the QNX headers: its heuristics mangle QNX's __WCHAR_T/__SIZE_T typedef
    # protocol (breaks wchar_t in libgcc). The pristine sysroot headers are
    # correct as-is; keep only GCC's own generated limits.h/syslimits.h.
    make -j$JOBS all-gcc
    find gcc/include-fixed -mindepth 1 \
        ! -name limits.h ! -name syslimits.h ! -name README \
        -prune -exec rm -rf {} +
    make -j$JOBS \
        CFLAGS_FOR_TARGET="$target_cflags" \
        CXXFLAGS_FOR_TARGET="$target_cxxflags"
    make install-strip \
        CFLAGS_FOR_TARGET="$target_cflags" \
        CXXFLAGS_FOR_TARGET="$target_cxxflags"
    # The port's libtool config installs only the shared libstdc++ (QNX
    # naming, no static archive); install the .a files so -static-libstdc++
    # works -- the sane way to deploy, since QNX 6.5 targets have no GCC 11
    # runtime libs.
    cp $target/libstdc++-v3/src/.libs/libstdc++.a \
       $target/libstdc++-v3/libsupc++/.libs/libsupc++.a \
       $PREFIX/$target/lib/

    # The QNX libtool configuration omits the top-level compatibility objects
    # from the installed static archive. Include every object produced there,
    # not a hand-maintained subset, so istream compatibility symbols and their
    # siblings are available to static links.
    local archive=$PREFIX/$target/lib/libstdc++.a object name missing=""
    for object in "$target"/libstdc++-v3/src/.libs/*.o; do
        name=$(basename "$object")
        "$PREFIX/bin/$target-ar" t "$archive" | grep -qx "$name" || \
            missing="$missing $object"
    done
    if [ -n "$missing" ]; then
        # Intentional splitting: ar expects the accumulated object paths as
        # separate arguments and build paths cannot contain whitespace here.
        # shellcheck disable=SC2086
        "$PREFIX/bin/$target-ar" r "$archive" $missing
        "$PREFIX/bin/$target-ranlib" "$archive"
    fi
}

case "${1:-all}" in
    sources)      sources ;;
    binutils-arm) binutils $ARM_TARGET ;;
    binutils-x86) binutils $X86_TARGET ;;
    gcc-arm)      sysroot_arm
                  gcc_build $ARM_TARGET $SYSROOT-armle-v7 \
                      --with-float=softfp --with-arch=armv7-a \
                      --with-fpu=vfpv3 ;;
    # i386/nto.h appends SYSROOT_SUFFIX_SPEC "/x86" (patch 0003) to this
    # sysroot for library/startfile searches -- qnx6/x86/lib etc., the real
    # QNX layout. Header search uses the unsuffixed sysroot.
    gcc-x86)      gcc_build $X86_TARGET $SYSROOT ;;
    # One step per line: a failure in an && chain would not trip `set -e`.
    all)          $0 sources
                  $0 binutils-arm
                  $0 binutils-x86
                  $0 gcc-arm
                  $0 gcc-x86
                  rm -rf $WORK ;;
    # ARM only. Use it for a sysroot with no x86 target tree
    # (Dockerfile.sdp-frida).
    all-arm)      $0 sources
                  $0 binutils-arm
                  $0 gcc-arm
                  rm -rf $WORK ;;
    *) echo "usage: $0 {sources|binutils-arm|binutils-x86|gcc-arm|gcc-x86|all|all-arm}" >&2
       exit 1 ;;
esac
