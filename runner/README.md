# Local GitHub Actions runner

This image runs the GitHub Actions runner and Podman in a separate container.
The outer container uses rootless Podman. Its root user maps to the host user.
It has no host Podman socket and no host project mounts.

The container requires `--privileged` for nested Podman and fuse-overlayfs.
It uses separate named volumes for runner state and container build storage.
The start script sets a CPU quota and a memory limit. The defaults are 12 CPUs
and 48 GiB. Set `RUNNER_CPUS` and `RUNNER_MEMORY` to change them. The CPU
count also sets the job count that `nproc` reports inside the runner, and
the compiler build uses one job per CPU unless the workflow `jobs` input
says otherwise. The script does not change an existing container with the
same name.

The compiler workflow uses the `qnx650-compiler` runner label. Only the manual
compiler workflow uses this runner. Pull-request source checks use GitHub-hosted
runners. Keep runner credentials and registration tokens out of Git.

## Restrict workflow runs from forks

A pull request from a fork runs the workflow file of that fork. That file can
name the `qnx650-compiler` runner label. Before you register the runner, open
the repository settings on GitHub, then Actions, then General. Under the fork
pull request workflow policy, select the option that requires approval for
all outside contributors. Then no fork can start a job on the runner without
a maintainer approval.

## Register the runner

Create the public GitHub repository first. Set the fork approval policy above.
Open the Actions runner settings.
Get a repository registration token. Save only that token in a private file.
Use mode `0600` for the file.

Run the script with the actual repository URL and token file:

```sh
runner/start.sh https://github.com/OWNER/qnx650-compiler /path/to/token-file
podman logs --timestamps qnx650-compiler-github-runner
```

The script creates the runner image, registers the runner, and starts it.
Inspect the log for a successful connection before you dispatch the compiler
workflow. Registration is separate from the local container tests.

The two state volumes contain private build inputs or credentials.
Do not publish them. Upload only the checked final compiler image.
