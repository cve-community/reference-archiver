#!/usr/bin/env bash
# Interactive setup for running the migration (MIGRATION.md) from this machine.
# Installs CLI tools, sets up an AWS profile and GitHub auth, verifies access,
# and writes non-secret settings to .operator.env (gitignored) for later use.
# Credentials stay in ~/.aws and the gh keyring; nothing secret is written here.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.operator.env"
REPO="cve-community/reference-archiver"
ARCHIVE_BUCKET="archiver-demo-v1-public"
STATE_BUCKET="vulncorps-tofu-s3-backend"
STATE_REGION="us-west-2"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
hdr()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ask()  { local p="$1" d="${2:-}" a; read -r -p "  $p${d:+ [$d]}: " a; echo "${a:-$d}"; }
yes()  { local a; read -r -p "  $1 [Y/n]: " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }

# --- 1. Tools ---------------------------------------------------------------
hdr "Tools (aws-cli, opentofu, actionlint)"
if command -v mise >/dev/null; then
  if yes "Pin aws-cli, opentofu and actionlint for this repo with mise (writes mise.toml)?"; then
    (cd "$ROOT" && mise use aws-cli@2 opentofu@1.10 actionlint@latest) || warn "mise install failed"
    eval "$(mise env -s bash -C "$ROOT")"
  fi
else
  warn "mise not found; install aws, tofu and actionlint yourself (e.g. brew install awscli opentofu actionlint)"
fi
for t in aws tofu actionlint; do
  if command -v "$t" >/dev/null && "$t" --version >/dev/null 2>&1; then ok "$t: $("$t" --version 2>&1 | head -1)"
  else bad "$t missing"; fi
done
command -v aws >/dev/null || { bad "aws is required to continue"; exit 1; }

# --- 2. AWS -----------------------------------------------------------------
hdr "AWS"
echo "  Needs admin in the account that owns s3://$ARCHIVE_BUCKET (applies infra/github-oidc by hand)."
existing="$(aws configure list-profiles 2>/dev/null | tr '\n' ' ')"
[[ -n "$existing" ]] && echo "  Existing profiles: $existing"
PROFILE="$(ask "Profile name to use" "cve-archiver")"

if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
  echo "  Profile '$PROFILE' doesn't work yet. How do you sign in?"
  echo "    1) IAM Identity Center / SSO"
  echo "    2) Access key + secret"
  echo "    3) It's configured; I just need to log in (SSO)"
  case "$(ask "Choice" "1")" in
    1) aws configure sso --profile "$PROFILE" ;;
    2) aws configure --profile "$PROFILE"
       aws configure set region us-east-1 --profile "$PROFILE" ;;
    3) aws sso login --profile "$PROFILE" ;;
  esac
fi

if ID="$(aws sts get-caller-identity --profile "$PROFILE" --output json 2>&1)"; then
  ACCOUNT_ID="$(jq -r .Account <<<"$ID")"; CALLER_ARN="$(jq -r .Arn <<<"$ID")"
  ok "Signed in as $CALLER_ARN (account $ACCOUNT_ID)"
else
  bad "Still can't authenticate: $ID"; exit 1
fi

aws s3api head-bucket --bucket "$ARCHIVE_BUCKET" --profile "$PROFILE" >/dev/null 2>&1 \
  && ok "Can see s3://$ARCHIVE_BUCKET" || bad "Can't access s3://$ARCHIVE_BUCKET (wrong account or no permission?)"
aws s3api head-object --bucket "$STATE_BUCKET" --key archiver-demo/terraform.tfstate \
  --region "$STATE_REGION" --profile "$PROFILE" >/dev/null 2>&1 \
  && ok "Can read tofu state s3://$STATE_BUCKET/archiver-demo/terraform.tfstate" \
  || bad "Can't read tofu state in s3://$STATE_BUCKET"
aws iam get-open-id-connect-provider --profile "$PROFILE" \
  --open-id-connect-provider-arn "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" >/dev/null 2>&1 \
  && ok "GitHub OIDC provider exists in account" || warn "GitHub OIDC provider not found (infra/github-oidc expects it)"

ECS_REGION="$(ask "Region of the old ECS cve-archiver cluster" "us-east-1")"
aws ecs describe-clusters --clusters cve-archiver-cluster --region "$ECS_REGION" --profile "$PROFILE" \
  --query 'clusters[0].status' --output text 2>/dev/null | grep -q ACTIVE \
  && ok "Found ECS cluster cve-archiver-cluster in $ECS_REGION" \
  || warn "ECS cluster cve-archiver-cluster not found in $ECS_REGION (may already be gone)"

# --- 3. GitHub --------------------------------------------------------------
hdr "GitHub"
gh auth status >/dev/null 2>&1 || gh auth login -h github.com -p ssh
scopes="$(gh auth status 2>&1 | grep -i 'token scopes' || true)"
if ! grep -q "'workflow'" <<<"$scopes"; then
  warn "Token lacks the 'workflow' scope (needed to dispatch workflows and change Actions settings)"
  yes "Add it now with gh auth refresh?" && gh auth refresh -h github.com -s workflow
fi
[[ "$(gh api "repos/$REPO" --jq .permissions.admin 2>/dev/null)" == "true" ]] \
  && ok "Admin on $REPO" || bad "Not admin on $REPO (needed for Actions, variables, environments, Pages)"
FORK="$(gh api "repos/$REPO" --jq '.fork' 2>/dev/null)"; echo "  $REPO fork: $FORK"
for r in VulnCorps/refgha VulnCorps/iac; do
  perm="$(gh api "repos/$r" --jq '.permissions | to_entries | map(select(.value)) | map(.key) | join(",")' 2>/dev/null)"
  [[ -n "$perm" ]] && ok "$r: $perm" || warn "No access to $r (needed for site cutover/decommission)"
done

# --- 4. Write settings ------------------------------------------------------
cat >"$OUT" <<EOF
# Written by scripts/operator-setup.sh on $(date -u +%FT%TZ). No secrets.
export AWS_PROFILE=$PROFILE
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$ACCOUNT_ID
export AWS_CALLER_ARN=$CALLER_ARN
export ECS_REGION=$ECS_REGION
export S3_BUCKET=$ARCHIVE_BUCKET
export GH_REPO=$REPO
EOF
hdr "Done"
ok "Wrote $OUT"
echo "  If you use SSO, rerun 'aws sso login --profile $PROFILE' when the session expires."
