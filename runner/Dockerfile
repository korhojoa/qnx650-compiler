FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90
ARG RUNNER_VERSION=2.337.0
ARG RUNNER_SHA256=70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl fuse-overlayfs git jq libicu74 libssl3t64 \
      nodejs podman procps python3 rsync tar uidmap zlib1g \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/actions-runner \
 && curl --fail --location --retry 3 --output /tmp/runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && printf '%s  /tmp/runner.tar.gz\n' "$RUNNER_SHA256" | sha256sum --check - \
 && tar -xzf /tmp/runner.tar.gz -C /opt/actions-runner \
 && rm /tmp/runner.tar.gz
COPY runner/storage.conf /etc/containers/storage.conf
COPY runner/entrypoint.sh /usr/local/bin/compiler-runner
ENV RUNNER_ALLOW_RUNASROOT=1 OMP_THREAD_LIMIT=4
WORKDIR /runner
ENTRYPOINT ["/usr/local/bin/compiler-runner"]
