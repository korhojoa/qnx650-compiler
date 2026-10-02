# Alternate media-based GNU build input.
# Mount the SDP media at /sdp and the answer file at /answers.txt.
# This intermediate image contains SDP files and stays local.

FROM ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03 AS installer

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libc6:i386 libstdc++6:i386 zlib1g:i386 && \
    rm -rf /var/lib/apt/lists/*

# The installer refuses to run from a full/read-only partition (the DVD mount
# reports 0 bytes free), so copy it somewhere writable first. Copy and
# install happen in one RUN so the ~750 MB installer doesn't persist in the
# layer. chmod: files extracted from the .iso (rather than a DVD mount) may
# lack the execute bit.
RUN mkdir /tmp/inst && \
    cp /sdp/qnx_linux_setup.jar /sdp/qnxsdp-6.5.0-201007091524-linux.bin /tmp/inst/ && \
    cd /tmp/inst && \
    chmod +x qnxsdp-6.5.0-201007091524-linux.bin && \
    sh -c '( cat /answers.txt; while :; do sleep 5; echo; done ) | ./qnxsdp-6.5.0-201007091524-linux.bin -console' && \
    rm -rf /tmp/inst && \
    test -x /opt/qnx650/host/linux/x86/usr/bin/qcc

# Modern GCC 11.2 cross-toolchains (C/C++) for both QNX targets, built from
# the QNX community GCC port against the SDP's target tree as sysroot.
# See build-toolchain.sh and patches/ for the details and QNX-6.5 fixes.
# ubuntu:26.04 is pinned by digest. The tag moves, so a bare `FROM
# ubuntu:26.04` would drift. The digest is an OCI image index, so it still
# resolves per architecture. GCC 11.2 builds under the host GCC 15 of this
# base, and the i386 multiarch libraries are present. To move the pin:
# change the digest, rebuild, and update sources.manifest together.
FROM ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03 AS gcc-builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev \
        flex bison texinfo file wget xz-utils patch ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=installer /opt/qnx650/target/qnx6 /opt/qnx650/target/qnx6
COPY patches /patches
COPY build-toolchain.sh /
RUN bash /build-toolchain.sh all

FROM ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libc6:i386 libstdc++6:i386 zlib1g:i386 \
        libgmp10 libmpfr6 libmpc3 \
        make ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=installer /opt/qnx650 /opt/qnx650
COPY --from=installer /etc/qnx /etc/qnx
COPY --from=gcc-builder /opt/gcc11 /opt/gcc11
# ARM sysroot view (symlinks into qnx6/); its path is baked into the ARM
# GCC at configure time.
COPY --from=gcc-builder /opt/qnx650/target/qnx6-armle-v7 /opt/qnx650/target/qnx6-armle-v7

ENV QNX_HOST=/opt/qnx650/host/linux/x86 \
    QNX_TARGET=/opt/qnx650/target/qnx6 \
    QNX_CONFIGURATION=/etc/qnx \
    MAKEFLAGS=-I/opt/qnx650/target/qnx6/usr/include \
    PATH=/opt/gcc11/bin:/opt/qnx650/host/linux/x86/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /src
CMD ["/bin/bash"]
