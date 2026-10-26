#!/usr/bin/env bash
# Fails if a tofu plan would destroy/replace any S3 resource or the Route53
# zone, or configure a lifecycle rule that expires *current* objects. The
# archive bucket is the only irreplaceable thing we run; this is the last line
# of defense in CI.
#
# Usage: infra-guard.sh <plan.json>   (from `tofu show -json plan.out`)
set -euo pipefail
PLAN_JSON="$1"

BAD_DELETES=$(jq -r '
  [.resource_changes[]?
   | select((.type | startswith("aws_s3_")) or .type == "aws_route53_zone")
   | select(.change.actions | index("delete"))
   | "\(.address) \(.change.actions | join("/"))"] | .[]' "$PLAN_JSON")

BAD_LIFECYCLE=$(jq -r '
  [.resource_changes[]?
   | select(.type == "aws_s3_bucket_lifecycle_configuration")
   | select(.change.after != null)
   | select([.change.after.rule[]?.expiration[]?] | length > 0)
   | .address] | .[]' "$PLAN_JSON")

if [ -n "$BAD_DELETES" ] || [ -n "$BAD_LIFECYCLE" ]; then
  echo "::error::infra-guard: plan touches archive data destructively"
  [ -n "$BAD_DELETES" ] && printf 'delete/replace: %s\n' $BAD_DELETES
  [ -n "$BAD_LIFECYCLE" ] && printf 'current-object expiration: %s\n' $BAD_LIFECYCLE
  exit 1
fi
echo "infra-guard: no destructive S3 or zone changes"
