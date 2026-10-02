#!/bin/sh
# Generate installer-answers.txt (console answers for the QNX SDP 6.5.0
# InstallShield wizard) from license.key, which must contain a single line
# of the form XXXX-XXXX-XXXX-XXXX-XXXX.
#
# Answer sequence: welcome, info screen, 5 license-key fields, next,
# quit EULA pager, accept EULA, done selecting, next, default install dir
# (/opt/qnx650), next, keep default features, next, install summary,
# post-install screens, finish. The Dockerfile appends blank lines after
# these, so trailing default-accepting screens are tolerant to drift.
set -eu
cd "$(dirname "$0")"

# This output contains the licence key; do not inherit a permissive umask.
umask 077

KEY=$(cat license.key)
case $KEY in
    ????-????-????-????-????) ;;
    *) echo "license.key must contain XXXX-XXXX-XXXX-XXXX-XXXX" >&2; exit 1 ;;
esac

{
    printf '1\n1\n'
    echo "$KEY" | tr '-' '\n'
    printf '1\nq\n1\n0\n1\n\n1\n0\n1\n1\n1\n1\n3\n'
} > installer-answers.txt
chmod 600 installer-answers.txt
echo "wrote installer-answers.txt"
