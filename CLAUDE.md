# CVE Program Reference Archiver

Fork of the CVE AWG reference-archiver pilot. The active implementation is GitHub Actions + ArchiveBox (Docker, one-shot per URL) + S3 + GitHub Pages; see README.md for workflows, storage layout and auth. Requirements: docs/prd_20250919.md.

The Node/ECS pilot (`src/`, `deploy/`, `docker/`, `package.json`, devcontainer) is upstream code kept for reference; don't extend it. Keep changes upstream-friendly: deployment-specific values (bucket, domain, state backend) belong in repo variables or clearly marked config, not scattered through code.

## Rules

- The S3 bucket `archiver-demo-v1-public` is the data and is irreplaceable. Never add anything that deletes or overwrites archived snapshots, weakens `prevent_destroy`, versioning, `scripts/infra-guard.sh`, or the IAM deny statements in `infra/github-oidc/`.
- Snapshot keys are append-only (new timestamp prefix per archive). Only derived files are rewritten: `v2/index.json`, `v2/index/*.json`, `v2/schedule.json`, `v2/state/*`.
- `infra/archive` adopts live resources via the existing state (`archiver-demo/terraform.tfstate`). Keep resource addresses stable; use `moved {}` blocks to rename.
- Scripting: Bash + jq + curl in workflows; Python 3 stdlib only for generators. No Node/pip installs.
- Under `set -o pipefail`, never `echo "$BIG" | head` — write to a file and `head` the file.
- Use `actions/*@v4` (upload/download-artifact v3 are deprecated).

## Local

- `act` for the `prepare` job (see DEV.md); archive/collect need real runners (Docker-in-Docker).
- `tofu fmt -recursive infra` before committing infra changes.
