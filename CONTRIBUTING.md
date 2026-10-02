# Contributing

Contributions can change the recipes, compatibility patches, tests, and
documentation. Submit only material that you can supply under the applicable
project and upstream licenses.

Do not submit QNX installer media, copied system headers, runtime libraries,
license keys, activation records, or logs that contain proprietary content.
Create small original test fixtures that a maintainer can inspect.

For an upstream change, identify the project, revision, changed paths, and
license. Keep upstream copyright and license notices intact. Apply patches
to the revision in `sources.manifest`.

Before submission, run:

```sh
scripts/check-release-readiness.sh
```

The complete compiler build uses an SDP-containing intermediate input.
Report test results without attaching that input, its layers, or its cache.
Only the checked final compiler image is a distribution candidate.
Use `SECURITY.md` for private reports of credential or proprietary-file exposure.
