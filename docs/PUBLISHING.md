# Publication procedure

The maintainer controls repository publication, runner registration, and image
uploads. Local preparation does not publish the source or register a runner.

## Review and publish the source

1. Inspect the source commits, README, third-party notices, and workflows.
2. Run the source checks and verify `SOURCE-FILES.sha256`.
3. Push the reviewed default branch to the Forgejo staging repository.
4. Inspect the staged source on Forgejo.
5. Create an empty public GitHub repository named `qnx650-compiler`.
6. Add that repository as a separate Git remote.
7. Push only the reviewed source branch to GitHub.
8. Inspect the GitHub source-check workflow result.

Do not transfer private toolchain history, container storage, or runner state.
The source tree has a new root commit and an explicit file inventory.

## Register the local runner

Use [the runner procedure](../runner/README.md). Set the fork pull request
approval policy in the GitHub repository settings before registration. The
token belongs to the GitHub repository. The Forgejo staging repository does
not supply this token. The runner uses its own state and container storage
volumes.

Confirm that GitHub shows the runner with the `qnx650-compiler` label before
you dispatch the compiler workflow.

## Assemble and publish the public package

1. Open the manual `compiler image` workflow on the default branch.
2. Use the `qnx650-compiler` runner label.
3. Set `publish` to `true` when an image upload is permitted.
4. Inspect the build and test results.
5. Record the printed image digest.
6. After the first upload, set the package visibility to Public.
7. Run the `public image check` workflow with that digest.
8. Use the verified digest in each consumer pipeline without registry credentials.

Set `publish` to `false` for a build check without an upload.
The workflow performs the complete source build and tests before an upload.
The final compiler image is the only upload input.

GitHub creates new packages with private visibility. The upload script checks
anonymous manifest access after the upload. If that check fails, it reports
the completed upload and exits with an error. Change the package visibility
in its settings, then run the separate public check. This check does not
rebuild the image. Later uploads to the public package can pass the check
in the upload workflow.

[GitHub package settings](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)
describe the visibility change.

Consumer projects must use the shared linker and their required native glue
steps. The image does not make an SDP-dependent project script compatible
without those script changes.
