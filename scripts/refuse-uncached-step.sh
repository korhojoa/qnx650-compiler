#!/bin/bash
# The build mounts this file in the place of /bin/sh for a stage that must
# come from the layer cache. Podman starts the shell only for a RUN step
# that has no cached layer, so this file stops the build at that step.
shift
printf 'No cached layer for this step:\n  %.300s\n' "$*" >&2
printf 'The build stops before the rebuild. Set REBUILD to let the stage build.\n' >&2
exit 1
