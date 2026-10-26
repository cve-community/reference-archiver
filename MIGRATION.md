# Migration: VulnCorps/refgha + VulnCorps/iac → cve-community/reference-archiver (fork)

Goal: this repo drives everything; the data in `s3://archiver-demo-v1-public` is untouched throughout.

## Status

- [x] refgha cron triggers removed (`VulnCorps/refgha@e32fa218`). `workflow_dispatch` still works there; don't use it after cutover.
- [x] §1 pre-flight (2026-10-26): no versioning, lifecycle or object lock; 463,624 objects / ~402 GB in `v2/`
- [x] ECS `cve-archiver-service` scaled to 0 (2026-10-26)
- [x] §2 `infra/github-oidc` applied (2026-10-26)
- [x] §4 infra adopted; versioning + noncurrent-only lifecycle live (2026-10-26)
- [x] ECS pilot torn down (2026-10-26, see §7)
- [ ] Steps below

## 1. Pre-flight (read-only, admin creds)

```sh
B=archiver-demo-v1-public
aws s3api get-bucket-versioning           --bucket $B   # expect empty = never enabled
aws s3api get-bucket-lifecycle-configuration --bucket $B   # if any rules exist, STOP: tofu would replace them
aws s3api get-object-lock-configuration   --bucket $B
aws s3 ls s3://$B/v2/ --recursive --summarize | tail -2     # object count + size, for the record
aws ecs describe-services --cluster cve-archiver-cluster --services cve-archiver-service \
  --query 'services[].{status:status,desired:desiredCount,running:runningCount}'
```

If the ECS `cve-archiver` service is running it also writes to this bucket. Scale it to 0 (don't destroy yet):
`aws ecs update-service --cluster cve-archiver-cluster --service cve-archiver-service --desired-count 0`

Optional belt-and-braces before the first apply: a one-time copy of `v2/` to a separate bucket (cost ≈ storage size).

## 2. OIDC roles (by hand, admin creds)

```sh
cd infra/github-oidc && tofu init && tofu plan && tofu apply
```

Creates 3 roles only; reuses the existing account OIDC provider. Nothing existing is modified.

## 3. Repo settings

- Actions tab: enable workflows (GitHub disables Actions, and all `schedule` triggers, on new forks)
- Make `main` the branch with this code (merge `claude/beautiful-maxwell-hmzm2c`); schedules only run on the default branch
- Variable `S3_BUCKET` (optional; defaults to `archiver-demo-v1-public`)

- Variables: `AWS_ROLE_ARN`, `AWS_INFRA_PLAN_ROLE_ARN`, `AWS_INFRA_APPLY_ROLE_ARN` (from step 2 outputs)
- Environment `infra`: required reviewer, deployment branch `main` only
- Actions → General → Workflow permissions: read
- Pages → Source: GitHub Actions (custom domain set in step 6)

## 4. Infra adoption

Dispatch `infra.yml` (or open a PR touching `infra/archive`). Expected plan, and nothing else:

- `+ aws_s3_bucket_versioning.archive`
- `+ aws_s3_bucket_lifecycle_configuration.archive` (noncurrent versions only)
- `null_resource.patch_lambda` removed from state (no API call)

Lambda code and the `origin-request` trigger match what's deployed (live drifted from `VulnCorps/iac` git on 2026-05-05; this repo adopts the live version), so no Lambda/CloudFront change is expected.

Anything else → stop and investigate. Approve the `infra` environment to apply.

After this, never run `VulnCorps/iac/aws/archiver/dirlist` again: this repo owns that state.

## 5. Pipeline cutover

1. Dispatch `crawl-cves.yml` with `dry_run=true`: confirms OIDC + S3 access; logs "seeded from state-seed/"
2. Dispatch `crawl-cves.yml` normally: writes `v2/state/*`, archives up to 15 CVEs
3. Verify `aws s3 ls s3://archiver-demo-v1-public/v2/state/`
4. Dispatch `rearchive.yml` with `dry_run=true`, then let schedules run

## 6. Site cutover

1. refgha → Settings → Pages: remove custom domain, then unpublish
2. Verify `cvearchiver.com` for the `cve-community` org (Settings → Pages → Verified domains) to prevent takeover
3. This repo → Settings → Pages → custom domain `cvearchiver.com`, enforce HTTPS
4. Dispatch `site.yml`

Apex DNS already points at GitHub Pages; no Route53 change expected.

## 7. Decommission (later, all recreatable — nothing here touches data)

- Deactivate (don't delete yet) the IAM access key behind refgha's `AWS_ACCESS_KEY_ID` secret; delete the repo secrets
- Archive `VulnCorps/refgha` and `VulnCorps/iac`
- [x] ECS pilot (`iac/aws/archiver/containers`) torn down by hand on 2026-10-26. It was crash-looping (its Supabase Postgres is gone) and was ~$50/mo of a ~$55/mo bill. Removed: service, cluster, task def, ALB + 6 public IPv4s, target group, SG `cve-archiver-sg`, IAM roles `ecsTaskExecutionRole`/`ecsTaskRole`, log group `/ecs/cve-archiver`, `api.cvearchiver.com` records + ACM cert. Secret `prod/archiver/settings` is scheduled for deletion (recoverable until 2026-11-25).
- **Never `tofu destroy` either old iac stack:**
  - `containers` declares the `cvearchiver.com` Route53 zone as a resource (`aws_route53_zone.cvearchiver`); destroying it would take the zone with it. Its local state is now stale; delete it, don't apply it.
  - `iac/aws/oidc` owns the GitHub OIDC provider that this repo's roles trust. Its `github-oidc-deployer` role (ReadOnly, trusts `VulnCorps/iac`) can go; the provider can't.
- Lambda@Edge log groups (`/aws/lambda/us-east-1.archiver-dirlist`, `/aws/cloudfront/LambdaEdge/*`) set to 30-day retention in every region by hand; they're created per edge region, outside tofu.

## Known issues carried over

- Throughput: 15 CVEs/hr vs cvelistV5 churn; spillover will grow. Tune `max_cves` / matrix `max-parallel` after cutover.
- `archivebox/archivebox` is unpinned (`latest`).
