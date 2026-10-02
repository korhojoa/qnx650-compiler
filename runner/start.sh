#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
url=${1:?usage: runner/start.sh GITHUB_REPOSITORY_URL REGISTRATION_TOKEN_FILE}
token=${2:?usage: runner/start.sh GITHUB_REPOSITORY_URL REGISTRATION_TOKEN_FILE}
[[ $url =~ ^https://github\.com/[A-Za-z0-9_.-]+/qnx650-compiler/?$ ]] || {
    echo 'Use the HTTPS URL of the GitHub qnx650-compiler repository.' >&2
    exit 2
}
token=$(realpath "$token")
[ -s "$token" ] || exit 2
image=localhost/qnx650-compiler-runner:local
name=qnx650-compiler-github-runner
# CPU quota and memory limit for the runner and every build inside it.
# The CPU count also sets the job count that nproc reports inside the runner.
cpus=${RUNNER_CPUS:-12}
memory=${RUNNER_MEMORY:-48g}
[[ $cpus =~ ^[1-9][0-9]*$ ]] || exit 2
[[ $memory =~ ^[1-9][0-9]*[gm]$ ]] || exit 2
if podman container exists "$name"; then
    echo "Container $name exists. Inspect it before a change." >&2
    exit 2
fi
podman build -f "$root/runner/Dockerfile" -t "$image" "$root"
podman run -d --name "$name" --privileged \
    --cpus "$cpus" --memory "$memory" --pids-limit 4096 \
    --restart unless-stopped \
    -e RUNNER_URL="$url" -e OMP_THREAD_LIMIT="$cpus" \
    -v qnx650-compiler-runner-state:/runner \
    -v qnx650-compiler-runner-storage:/var/lib/containers \
    -v "$token:/run/secrets/registration-token:ro" \
    "$image"
echo "Runner container: $name"
