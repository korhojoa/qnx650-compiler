# Security policy

Report credential exposure, committed QNX material, unsafe download checks,
or container vulnerabilities through the host's private security report system.
Do not put credentials, proprietary files, private endpoints, or exploit
instructions in a public issue.

Identify the affected revision, file, impact, and safe reproduction steps.
Remove credentials and private host information from the report.

The final compiler image and the SDP-containing build inputs have different
release boundaries. The build inputs, intermediate images, caches, and runner
state remain private. Review the final image before a registry upload.
The final compiler package is public. Verify anonymous access to its exact
digest before a public release announcement.
