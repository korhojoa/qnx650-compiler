#!/bin/bash
# In-container build steps for the GCC 16.1 QNX 6.5 cross-toolchain.
# Dockerfile.gcc16 runs it with GCC16_ROOT and GCC16_PREFIX set. It can also
# run in a container with the repository mounted at /work.
#
# Source tree: $GCC16_ROOT/gcc-16.1.0 with gcc16-qnx650.patch applied.
# Build directories and the install prefix live under $GCC16_ROOT.
set -euo pipefail

GCC16=${GCC16_ROOT:-/work/gcc-work/gcc16}
SRC=$GCC16/gcc-16.1.0
PREFIX=${GCC16_PREFIX:-$GCC16/opt-gcc16}
SYSROOT=/opt/qnx650/target/qnx6
OLDBIN=/opt/gcc11/bin           # binutils 2.42 for both targets lives here
MAKE=/usr/bin/make              # NOT the SDP make 3.81 that shadows it
JOBS=$(nproc)

ARM_TARGET=arm-unknown-nto-qnx6.5.0eabi
X86_TARGET=i386-pc-nto-qnx6.5.0

# Target-library flags. ARM: -mno-unaligned-access is MANDATORY -- the
# supported ARM targets run with SCTLR.A=1, and GCC's default
# -munaligned-access merges adjacent byte stores into unaligned halfword/word
# ops (seen on a target: SIGBUS BUS_ADRALN in __moneypunct_cache ctor, strh
# [r3,#17], during
# iostream init; gcc11's libstdc++ has the same class of fault in
# _Hash_bytes). -Wno-narrowing: QNX PTHREAD_*_INITIALIZER carries 0x80000000
# in int fields; C++11 list-init rejects it during the libstdc++ build.
ARM_CF_TGT="-g -O2 -mno-unaligned-access"
ARM_CXXF_TGT="-g -O2 -Wno-narrowing -mno-unaligned-access"
X86_CF_TGT="-g -O2"
X86_CXXF_TGT="-g -O2 -Wno-narrowing"

export PATH="$PREFIX/bin:$OLDBIN:/usr/local/bin:/usr/bin:/bin:/opt/qnx650/host/linux/x86/usr/bin"

configure_gcc() { # $1 target, $2 sysroot, rest = extra flags
    local target=$1 sysroot=$2; shift 2
    mkdir -p $GCC16/build/gcc-$target
    cd $GCC16/build/gcc-$target
    $SRC/configure \
        --target=$target \
        --prefix=$PREFIX \
        --with-sysroot=$sysroot \
        --with-as=$OLDBIN/$target-as \
        --with-ld=$OLDBIN/$target-ld \
        --enable-languages=c,c++ \
        --enable-gnu-indirect-function=no \
        --with-system-zlib \
        --enable-threads=posix \
        --enable-__cxa_atexit \
        --enable-shared \
        --enable-static \
        --disable-largefile \
        --disable-werror \
        --disable-nls \
        --disable-tls \
        --disable-libssp \
        --disable-libstdcxx-pch \
        --disable-libsanitizer \
        --disable-libgomp \
        --disable-bootstrap \
        "$@"
}

# Build compiler proper, prune fixincludes (QNX __WCHAR_T typedef protocol --
# fixincludes mangles it; pristine sysroot headers are correct), then the
# target libs, then install + static libstdc++ archives.
build_gcc() { # $1 target, $2 CFLAGS_FOR_TARGET, $3 CXXFLAGS_FOR_TARGET
    local target=$1 cf=$2 cxxf=$3
    cd $GCC16/build/gcc-$target
    $MAKE -j$JOBS all-gcc
    find gcc/include-fixed -mindepth 1 \
        ! -name limits.h ! -name syslimits.h ! -name README \
        -prune -exec rm -rf {} +
    $MAKE -j$JOBS CFLAGS_FOR_TARGET="$cf" CXXFLAGS_FOR_TARGET="$cxxf"
    $MAKE install-strip CFLAGS_FOR_TARGET="$cf" CXXFLAGS_FOR_TARGET="$cxxf"
    cp $target/libstdc++-v3/src/.libs/libstdc++.a \
       $target/libstdc++-v3/libsupc++/.libs/libsupc++.a \
       $PREFIX/$target/lib/
}

# Fixup 4 (both targets): QNX-defer wrapper for GCC's internal stddef.h and
# stdarg.h -- the SAME fix Dockerfile.tools applies to gcc11. QNX libc headers
# (limits.h -> sys/platform.h) predefine the _GCC_*/__WCHAR_T guard macros,
# so GCC's internal stddef.h skips its typedefs and any TU that includes a
# QNX header before <stddef.h> loses wchar_t/ptrdiff_t (first seen in ICU 70
# makeconv). Defer to the sysroot
# header (which knows the guard dance) and supply max_align_t (QNX stddef.h
# predates C11). Idempotent: skips if the wrapper is already in place.
wrap_internal_headers() { # $1 target
    local d=$PREFIX/lib/gcc/$1/16.1.0/include h f
    for h in stddef.h stdarg.h; do
        f=$d/$h
        grep -q __QNXNTO__ "$f" && continue
        { printf '#ifdef __QNXNTO__\n#include_next <%s>\n' "$h"
          if [ "$h" = stddef.h ]; then
            printf '#if (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L) \\\n'
            printf '    || (defined(__cplusplus) && __cplusplus >= 201103L)\n'
            printf '#ifndef _GCC_MAX_ALIGN_T\n#define _GCC_MAX_ALIGN_T\n'
            printf 'typedef struct {\n'
            printf '  long long __max_align_ll __attribute__((__aligned__(__alignof__(long long))));\n'
            printf '  long double __max_align_ld __attribute__((__aligned__(__alignof__(long double))));\n'
            printf '} max_align_t;\n#endif\n#endif\n'
          fi
          printf '#else\n'
          cat "$f"
          printf '\n#endif /* __QNXNTO__ */\n'; } > "$f.new"
        mv "$f.new" "$f"
        echo "$1/$h: QNX-defer wrapper applied"
    done
}

# C++23 `import std`. The libstdc++ build compiles the std and std.compat
# module units before the fixups below enable the C99 blocks in
# c++config.h. Thus that compile fails (stoll, snprintf and more are not in
# std), and the libstdc++ Makefile then installs an EMPTY bits/std.cc.
# This function installs the real units after the c++config.h fixup. It
# joins <unit>.cc.in and std-clib.cc.in, as the Makefile does. Then it
# compiles both units and an importer with the installed compiler. The
# units set _QNX_SOURCE themselves (gcc16-qnx650.patch).
install_std_module() { # $1 target
    local d=$PREFIX/$1/include/c++/16.1.0/bits m t
    for m in std std.compat; do
        cat $SRC/libstdc++-v3/src/c++23/$m.cc.in \
            $SRC/libstdc++-v3/src/c++23/std-clib.cc.in > $d/$m.cc
    done
    t=$(mktemp -d)
    ( cd $t
      printf 'import std;\nint main() { std::println("{}", std::llabs(-1LL)); }\n' > use.cpp
      $PREFIX/bin/$1-g++ -std=gnu++23 -fmodules -c $d/std.cc -o std.o
      $PREFIX/bin/$1-g++ -std=gnu++23 -fmodules -c $d/std.compat.cc -o std.compat.o
      $PREFIX/bin/$1-g++ -std=gnu++23 -fmodules -c use.cpp -o use.o )
    rm -rf $t
    echo "$1: std and std.compat module units installed and verified"
}

case "${1:?stage}" in
    conf-arm)  configure_gcc $ARM_TARGET $SYSROOT-armle-v7 \
                   --with-float=softfp --with-arch=armv7-a --with-fpu=vfpv3 ;;
    gcc-arm)   cd $GCC16/build/gcc-$ARM_TARGET && $MAKE -j$JOBS all-gcc ;;
    prune-arm) cd $GCC16/build/gcc-$ARM_TARGET && \
               find gcc/include-fixed -mindepth 1 \
                   ! -name limits.h ! -name syslimits.h ! -name README \
                   -prune -exec rm -rf {} + ;;
    libs-arm)  cd $GCC16/build/gcc-$ARM_TARGET && \
               $MAKE -j$JOBS CFLAGS_FOR_TARGET="$ARM_CF_TGT" CXXFLAGS_FOR_TARGET="$ARM_CXXF_TGT" ;;
    inst-arm)  cd $GCC16/build/gcc-$ARM_TARGET && \
               $MAKE install-strip CFLAGS_FOR_TARGET="$ARM_CF_TGT" CXXFLAGS_FOR_TARGET="$ARM_CXXF_TGT" && \
               cp $ARM_TARGET/libstdc++-v3/src/.libs/libstdc++.a \
                  $ARM_TARGET/libstdc++-v3/libsupc++/.libs/libsupc++.a \
                  $PREFIX/$ARM_TARGET/lib/ ;;
    # Post-install fixups (mirrors the gcc11 Dockerfile.tools fixes):
    # 1. The QNX libtool drops the eight top-level src/ compatibility-*.o
    #    objects from the installed libstdc++.a (gcc11 had the same bug --
    #    one-arg istream::ignore lived there and static links of wcin/wcout
    #    failed). Append them from the build tree + ranlib.
    # 2. QNX 6.5 libc HAS the C99 stdlib/stdio functions (strtoll, vsnprintf,
    #    ...) but the cross configure cannot probe them -- enable the
    #    _GLIBCXX*_USE_C99_STDLIB/STDIO blocks under _QNX_SOURCE only (without
    #    _QNX_SOURCE the QNX headers hide the underlying C declarations).
    fixup-arm)
        wrap_internal_headers $ARM_TARGET
        B=$GCC16/build/gcc-$ARM_TARGET/$ARM_TARGET/libstdc++-v3
        A=$PREFIX/$ARM_TARGET/lib/libstdc++.a
        missing=""
        for o in $B/src/.libs/*.o; do
            n=$(basename $o)
            $OLDBIN/$ARM_TARGET-ar t $A | grep -qx "$n" || missing="$missing $o"
        done
        if [ -n "$missing" ]; then
            $OLDBIN/$ARM_TARGET-ar r $A $missing
            $OLDBIN/$ARM_TARGET-ranlib $A
            echo "appended:$missing"
        fi
        f=$PREFIX/$ARM_TARGET/include/c++/16.1.0/$ARM_TARGET/bits/c++config.h
        for m in _GLIBCXX11_USE_C99_STDLIB _GLIBCXX98_USE_C99_STDLIB \
                 _GLIBCXX11_USE_C99_STDIO  _GLIBCXX98_USE_C99_STDIO; do
            sed -i "s@^/\* #undef $m \*/\$@#ifdef _QNX_SOURCE\n# define $m 1\n#endif@" "$f"
        done
        grep -q '# define _GLIBCXX11_USE_C99_STDLIB 1' "$f"
        grep -q '# define _GLIBCXX11_USE_C99_STDIO 1' "$f"
        echo "c++config.h C99 blocks enabled"
        install_std_module $ARM_TARGET
        # 3. ARM EHABI exidx: binutils armnto ldscripts predate ARM EH and
        #    never merge .ARM.exidx orphan sections, so PT_ARM_EXIDX covers
        #    almost nothing and QNX libc.so.3's runtime unwinder (which
        #    provides _Unwind_RaiseException!) finds no unwind entries -->
        #    every C++ throw aborts. Fix: INSERT linker script merging the
        #    canonical sections (verified: single sorted table, phdr covers
        #    it), auto-added to every link via an installed driver specs
        #    file appending to *link. gcc11 has the same latent defect.
        #    NB: the auto-loaded libdir specs file must be a COMPLETE
        #    -dumpspecs dump (a partial file silently resets the builtin
        #    specs -- lost the endian defines when tried); dump + edit *link.
        cp $GCC16/exidx-merge.ld $PREFIX/$ARM_TARGET/lib/
        # 4. Driver DEFAULTS -mno-unaligned-access (SCTLR.A=1 targets; a
        #    manual flag still works, but no compile can forget it
        #    now). Appended to both *cc1 (C) and *cc1plus (C++);
        #    %{!munaligned-access:} keeps an explicit opt-in working.
        SPECS=$PREFIX/lib/gcc/$ARM_TARGET/16.1.0/specs
        $PREFIX/bin/$ARM_TARGET-gcc -dumpspecs > /tmp/full.specs
        python3 - <<'PYEOF'
s = open('/tmp/full.specs').read()
def append_spec(s, name, add):
    i = s.index('*' + name + ':\n')
    j = s.index('\n', i + len(name) + 3)
    if add not in s[i:j]:
        s = s[:j] + add + s[j:]
    return s
s = append_spec(s, 'link', ' %{!r:%{!T*:-T exidx-merge.ld%s}}')
for spec in ('cc1', 'cc1plus'):
    s = append_spec(s, spec, ' %{!munaligned-access:-mno-unaligned-access}')
# 5. Static-libc second pass: 100+ libc functions (regcomp/glob/wordexp/
#    ...) exist ONLY in libc.a/libcS.a, never libc.so.3; stock 4.4 links
#    "-lc -Bstatic -lc" but the qnx_11_2-derived LIB_SPEC lost the second
#    pass. Append -l:libc.a (-lcS for pie) to the exe branch only -- no
#    libc.a leak into shared links (non-PIC members = TEXTRELs). Same fix
#    as gcc11's gcc11-staticlibc-specs.py. A comparison with the
#    luka-dev/qnx65-armv7-toolchain repository, which has no license file,
#    showed the gap.
i = s.index('*lib:\n'); j = s.index('\n', i + 6)
old = '%{no-pie:-lc}}'
new = '%{!shared:%{!pie:-l:libc.a}}}'
assert old in s[i:j] or new in s[i:j], 'unexpected *lib spec: ' + s[i:j]
s = s[:i] + s[i:j].replace(old, new) + s[j:]
open('/tmp/full.specs', 'w').write(s)
PYEOF
        cp /tmp/full.specs $SPECS
        echo "specs installed (full dump + *link exidx + *cc1/*cc1plus no-unaligned + *lib static libc.a)"
        ;;
    all-arm)   $0 conf-arm; build_gcc $ARM_TARGET "$ARM_CF_TGT" "$ARM_CXXF_TGT"; $0 fixup-arm ;;
    fixup-x86)
        wrap_internal_headers $X86_TARGET
        B=$GCC16/build/gcc-$X86_TARGET/$X86_TARGET/libstdc++-v3
        A=$PREFIX/$X86_TARGET/lib/libstdc++.a
        missing=""
        for o in $B/src/.libs/*.o; do
            n=$(basename $o)
            $OLDBIN/$X86_TARGET-ar t $A | grep -qx "$n" || missing="$missing $o"
        done
        if [ -n "$missing" ]; then
            $OLDBIN/$X86_TARGET-ar r $A $missing
            $OLDBIN/$X86_TARGET-ranlib $A
            echo "appended:$missing"
        fi
        f=$PREFIX/$X86_TARGET/include/c++/16.1.0/$X86_TARGET/bits/c++config.h
        for m in _GLIBCXX11_USE_C99_STDLIB _GLIBCXX98_USE_C99_STDLIB \
                 _GLIBCXX11_USE_C99_STDIO  _GLIBCXX98_USE_C99_STDIO; do
            sed -i "s@^/\* #undef $m \*/\$@#ifdef _QNX_SOURCE\n# define $m 1\n#endif@" "$f"
        done
        grep -q '# define _GLIBCXX11_USE_C99_STDLIB 1' "$f"
        echo "x86 c++config.h C99 blocks enabled"
        install_std_module $X86_TARGET
        # Static-libc second pass, same as fixup-arm step 5 (x86 had no
        # specs file before -- install a COMPLETE dump with only *lib
        # edited; a partial file silently resets builtin specs).
        SPECS=$PREFIX/lib/gcc/$X86_TARGET/16.1.0/specs
        $PREFIX/bin/$X86_TARGET-gcc -dumpspecs > /tmp/full.specs
        python3 - <<'PYEOF'
s = open('/tmp/full.specs').read()
i = s.index('*lib:\n'); j = s.index('\n', i + 6)
# x86 keeps the i386 nto.h LIB_SPEC shape, not the ARM nto-eabi.h one.
old = '%{!shared:%{!symbolic:-lc}}'
new = '%{!shared:%{!symbolic:-lc %{pie:-lcS} %{!pie:-l:libc.a}}}'
assert old in s[i:j] or new in s[i:j], 'unexpected *lib spec: ' + s[i:j]
s = s[:i] + s[i:j].replace(old, new) + s[j:]
open('/tmp/full.specs', 'w').write(s)
PYEOF
        cp /tmp/full.specs $SPECS
        echo "x86 specs installed (full dump + *lib static libc.a)"
        ;;
    # i386/nto.h appends SYSROOT_SUFFIX_SPEC "/x86" itself, so the plain
    # sysroot is correct here (library search becomes qnx6/x86/lib etc.).
    conf-x86)  configure_gcc $X86_TARGET $SYSROOT ;;
    all-x86)   $0 conf-x86; build_gcc $X86_TARGET "$X86_CF_TGT" "$X86_CXXF_TGT"; $0 fixup-x86 ;;
    clean)     rm -rf $GCC16/build $PREFIX ;;
    shell)     exec bash ;;
    *) echo "usage: $0 {conf-arm|gcc-arm|prune-arm|libs-arm|inst-arm|all-arm|conf-x86|all-x86|clean}" >&2; exit 1 ;;
esac
