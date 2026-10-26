# Removing archived content (PRD 3.5)

Manual procedure for a CNA/owner takedown request. No CI role can delete objects (by design), so this is done by an account admin with their own credentials.

The bucket is **versioned**: deleting an object only adds a delete marker and the content stays retrievable via its version ID. A takedown must delete every version.

## 1. Find the snapshots

Snapshot keys are derived from the reference URL:

```
v2/<host>/<path>[__q__<url-encoded query>]/<YYYYMMDD-HHMMSS>/{output.pdf,screenshot.png,warc.tgz}
```

```sh
B=archiver-demo-v1-public
P='v2/example.com/advisories/2025-001'          # URL → prefix, no trailing timestamp
aws s3api list-object-versions --bucket $B --prefix "$P/" \
  --query '[Versions[].{K:Key,V:VersionId}, DeleteMarkers[].{K:Key,V:VersionId}][]' --output text
```

Check the listing is exactly the content to remove before going further. A short prefix can match other URLs (`/advisories/2025-001` also matches `/advisories/2025-0010`), so keep the trailing `/`.

## 2. Delete every version

```sh
aws s3api list-object-versions --bucket $B --prefix "$P/" \
  --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][]}' \
  --output json > /tmp/takedown.json
aws s3api delete-objects --bucket $B --delete file:///tmp/takedown.json
```

## 3. Clean up derived data

- Per-CVE indexes that list the URL: `v2/index/<CVE-ID>.json`. Remove the matching entries from `snapshots[]` and re-upload.
- `v2/index.json` and the site data are rebuilt from the S3 listing on the next crawl and site run. Dispatch `site.yml` to publish now.
- Invalidate CloudFront: `aws cloudfront create-invalidation --distribution-id <id> --paths "/$P/*"`

## 4. Prevent re-archiving

The URL will be archived again the next time its CVE is crawled or hits a re-archive interval. There is no denylist yet; until there is, record the takedown and repeat the check after the CVE's 90-day interval.
