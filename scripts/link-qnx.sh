#!/usr/bin/env bash
# The Cargo linker for armv7-unknown-nto-qnx650: a shared library goes to
# link-qnx-shared.sh, anything else to link-qnx-exe.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
for arg do
    if [ "$arg" = -shared ]; then
        exec "$here/link-qnx-shared.sh" "$@"
    fi
done
exec "$here/link-qnx-exe.sh" "$@"
