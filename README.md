# CVE Program Reference Archiver

Monitors [CVEProject/cvelistV5](https://github.com/CVEProject/cvelistV5) for new and updated CVEs, archives every reference URL with ArchiveBox (PDF + screenshot + WARC) to S3, and serves a static browse/search UI.

**Browse:** [cvearchiver.com](https://cvearchiver.com) · **Stats:** [cvearchiver.com/stats.html](https://cvearchiver.com/stats.html) · **Raw archive:** [archive.cvearchiver.com](https://archive.cvearchiver.com)

Everything runs on GitHub Actions + S3. No servers, no database.

This is the GitHub Actions implementation of the [AWG Reference Archive PRD](docs/prd_20250919.md). The original Node/ECS pilot (`src/`, `deploy/`, `docker/`) is still in the tree, unchanged; see [docs/pilot-node.md](docs/pilot-node.md).

## PRD coverage

| PRD   | Requirement                                   | Status |
| ----- | --------------------------------------------- | ------ |
| 2.1   | Archive every reference in a CVE record       | CNA container only; ADP references not yet |
| 2.2   | PNG + PDF + WARC                              | Done |
| 2.3   | Public retrieval by CVE ID + interval, as ZIP | Browse by CVE/domain on the site; per-file via archive.cvearchiver.com; no ZIP or interval selector yet |
| 2.4   | 0/3/10/30/90-day intervals                    | Done (`rearchive.yml`, `schedule.json`) |
| 3.1–3.4 | Scalable, simple, low-maintenance, cheap    | GHA + S3 only; throughput tuning pending (see MIGRATION.md) |
| 3.5   | Documented removal procedure                  | [docs/removal.md](docs/removal.md) |
| 5.1   | Don't archive 404s                            | Not yet |
| 5.5   | Content size limits                           | Not yet |

## Workflows

| Workflow            | Trigger                  | Purpose                                                |
| ------------------- | ------------------------ | ------------------------------------------------------ |
| `crawl-cves.yml`    | self-chained (see below) | Walk new cvelistV5 commits, archive up to 100 CVEs/run |
| `rearchive.yml`     | after each crawl         | Re-archive on the 3/10/30/90-day schedule              |
| `site.yml`          | after archiving, site edits | Build site + stats from S3, deploy to GitHub Pages  |
| `archive-cve.yml`   | manual / `workflow_call` | Archive all refs for one CVE                           |
| `batch-archive.yml` | manual                   | Archive a list of CVEs                                 |
| `infra.yml`         | PR / push on `infra/`    | `tofu plan` on PR; guarded `apply` on main (approval)  |

`crawl-cves` and `rearchive` share the `cve-archiving` concurrency group: they never overlap, so `schedule.json` has a single writer at a time.

The `schedule:` triggers are still in the files but never fire in this repo (it is a fork; GitHub doesn't run schedules here). Instead each run's `chain` job dispatches the next one: crawl → rearchive → crawl. Set the repo variable `AUTO_CHAIN` to anything but `true` to stop the loop; `gh workflow run crawl-cves.yml` restarts it.

## Storage

```
s3://archiver-demo-v1-public/v2/
├── <domain>/<path>[__q__<query>]/<YYYYMMDD-HHMMSS>/{output.pdf,screenshot.png,warc.tgz}
├── index/<CVE-ID>.json     # per-CVE reference list + snapshot prefixes
├── index.json              # global URL index (rebuilt from listing)
├── schedule.json           # re-archive ledger
└── state/                  # crawl cursor + spillover queue
    ├── last-processed-sha
    └── spillover-cves.txt
```

The bucket is the only irreplaceable thing here. Protections:

- `prevent_destroy` on the bucket; versioning on, noncurrent versions kept 30 days
- `scripts/infra-guard.sh` fails any plan that deletes/replaces an `aws_s3_*` resource or expires current objects
- No CI role has `s3:DeleteObject`, `s3:DeleteObjectVersion` or `s3:DeleteBucket` (explicit deny)

## Layout

```
.github/workflows/   pipeline + infra CI
scripts/             site/stats generators, index rebuild, infra guard
site/                static SPA (data/ and stats.html generated at deploy)
state-seed/          crawl cursor carried over from VulnCorps/refgha; used only if S3 state is absent
infra/archive/       bucket, CloudFront + Lambda@Edge dirlist, DNS/ACM (CI-applied)
infra/github-oidc/   OIDC roles for this repo (applied by hand by an admin)
docs/                PRD, requirements, removal procedure, pilot docs
src/ deploy/ docker/ Node/ECS pilot (upstream, inactive)
```

## Auth

GitHub OIDC only, no static keys. Repo variables:

| Variable                   | Role                            | Used by                         |
| -------------------------- | ------------------------------- | ------------------------------- |
| `AWS_ROLE_ARN`             | `reference-archiver-runtime`    | pipeline (main only)            |
| `AWS_INFRA_PLAN_ROLE_ARN`  | `reference-archiver-infra-plan` | `infra.yml` plan (read-only)    |
| `AWS_INFRA_APPLY_ROLE_ARN` | `reference-archiver-infra-apply`| `infra.yml` apply (`infra` env) |

See [MIGRATION.md](MIGRATION.md) for the cutover from `VulnCorps/refgha` + `VulnCorps/iac`.
