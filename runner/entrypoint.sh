#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_URL:?Set RUNNER_URL to the GitHub repository URL}"
cd /runner
if [ ! -x ./run.sh ]; then
    cp -a /opt/actions-runner/. ./
fi
if [ ! -f .runner ]; then
    token_file=/run/secrets/registration-token
    [ -s "$token_file" ] || {
        echo 'A GitHub runner registration token file is necessary.' >&2
        exit 2
    }
    ./config.sh --unattended --url "$RUNNER_URL" \
        --token "$(cat "$token_file")" \
        --name "${RUNNER_NAME:-qnx650-compiler}" \
        --labels qnx650-compiler --work _work
fi
exec ./run.sh
