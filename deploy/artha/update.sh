#!/usr/bin/env bash
# Auto-update pipeline for Artha Automations.
#
# Tracks upstream Activepieces releases and ships them to the live Scalingo app
# with the Artha white-label layer re-applied — the same fork-tracks-upstream
# model used by Artha's other rebranded repos.
#
# Flow:
#   1. resolve the latest stable upstream version (skips -rc/-alpha/-beta)
#   2. stop if we are already on it (unless --force)
#   3. build the rebranded slug FROM the upstream image at that version
#      (rebrand.sh asserts every branded token — if upstream text drifted the
#       build FAILS LOUDLY here instead of shipping a half-branded slug)
#   4. publish the slug as a GitHub release asset
#   5. point Scalingo AP_SLUG_URL at it and trigger a redeploy
#   6. verify the live app serves HTTP 200 with the Artha title
#   7. bump deploy/artha/VERSION
#
#   --dry-run [version]   run steps 1-3 only (resolve + build + assert). Proves
#                         the rebrand still applies to new upstream without
#                         touching the release or production. Exit 0 = safe to
#                         ship; non-zero = upstream drifted, needs a human.
#   --force               rebuild/redeploy even if already on the target version
#   <version>             target a specific version instead of "latest stable"
#
# Required env:
#   GH_TOKEN              GitHub token with repo scope (release upload + push)
# Required for a real (non-dry-run) deploy, one of:
#   SCALINGO_API_TOKEN    preferred for headless/scheduled runs
#   (or) an already-logged-in scalingo CLI session
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────────
UPSTREAM_REPO="activepieces/activepieces"
FORK_REPO="bytepassperks/artha-automations"
SCALINGO_APP="artha-automations"
SCALINGO_REGION="osc-fr1"
LIVE_URL="https://artha-automations.osc-fr1.scalingo.io"
EXPECTED_TITLE="<title>Artha Automations</title>"
VERSION_FILE="$HERE/VERSION"
SLUG_OUT="$HERE/dist/ap-slug.tar.gz"

DRY_RUN=0
FORCE=0
TARGET_VERSION=""

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '\n !  %s\n' "$*" >&2; }
die()  { printf '\n !! %s\n' "$*" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    -*)        die "unknown flag: $1" ;;
    *)         TARGET_VERSION="$1" ;;
  esac
  shift
done

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is required (repo scope)."

gh_api() {
  curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" "$@"
}

# Pick the highest stable semver from the upstream releases (skip pre-releases
# and any tag carrying an -rc/-alpha/-beta suffix, which upstream sometimes
# mislabels as non-prerelease).
resolve_latest_stable() {
  gh_api "https://api.github.com/repos/$UPSTREAM_REPO/releases?per_page=50" \
  | python3 -c '
import sys, json, re
rels = json.load(sys.stdin)
def parse(tag):
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag)
    return tuple(int(x) for x in m.groups()) if m else None
best, best_tag = None, None
for r in rels:
    if r.get("prerelease") or r.get("draft"):
        continue
    key = parse(r["tag_name"])
    if key and (best is None or key > best):
        best, best_tag = key, r["tag_name"]
print(best_tag or "")
'
}

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[ -n "$CURRENT_VERSION" ] || die "could not read current version from $VERSION_FILE"

if [ -z "$TARGET_VERSION" ]; then
  log "Resolving latest stable upstream release of $UPSTREAM_REPO"
  TARGET_VERSION="$(resolve_latest_stable)"
  [ -n "$TARGET_VERSION" ] || die "could not resolve a latest stable upstream version"
fi

log "current: $CURRENT_VERSION   target: $TARGET_VERSION   dry-run: $DRY_RUN   force: $FORCE"

if [ "$TARGET_VERSION" = "$CURRENT_VERSION" ] && [ "$FORCE" -ne 1 ]; then
  log "Already on $CURRENT_VERSION — nothing to do."
  exit 0
fi

# ── Step 3: build the rebranded slug (rebrand assertions guard upstream drift) ─
log "Building rebranded slug for upstream $TARGET_VERSION"
if ! "$HERE/build-slug.sh" "$TARGET_VERSION" "$SLUG_OUT"; then
  die "slug build FAILED for $TARGET_VERSION.
      The rebrand layer could not be applied cleanly — upstream text likely
      drifted (a rebrand.sh assertion or the Dockerfile transport patch failed).
      This needs a human to update deploy/artha/rebrand.sh before $TARGET_VERSION
      can ship. Production was NOT touched."
fi
log "Slug built OK: $SLUG_OUT ($(du -h "$SLUG_OUT" | cut -f1)) — rebrand applied cleanly."

if [ "$DRY_RUN" -eq 1 ]; then
  log "DRY-RUN complete. Upstream $TARGET_VERSION rebrands cleanly and is safe to ship."
  log "Run without --dry-run to publish + deploy."
  exit 0
fi

# ── Step 4: publish the slug as a GitHub release asset ────────────────────────
RELEASE_TAG="deploy-${TARGET_VERSION}-artha"
ASSET_NAME="ap-slug.tar.gz"
ASSET_URL="https://github.com/$FORK_REPO/releases/download/$RELEASE_TAG/$ASSET_NAME"

log "Publishing slug to release $RELEASE_TAG"
REL_ID="$(gh_api "https://api.github.com/repos/$FORK_REPO/releases/tags/$RELEASE_TAG" 2>/dev/null \
          | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
if [ -z "$REL_ID" ]; then
  REL_ID="$(gh_api -X POST "https://api.github.com/repos/$FORK_REPO/releases" \
    -d "{\"tag_name\":\"$RELEASE_TAG\",\"name\":\"$RELEASE_TAG\",\"body\":\"Rebranded Activepieces $TARGET_VERSION slug for Scalingo (AP_SLUG_URL).\"}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"
  log "created release $RELEASE_TAG (id $REL_ID)"
else
  log "release $RELEASE_TAG already exists (id $REL_ID) — replacing asset"
  OLD_ASSET_ID="$(gh_api "https://api.github.com/repos/$FORK_REPO/releases/$REL_ID/assets" \
    | python3 -c "import sys,json;print(next((a['id'] for a in json.load(sys.stdin) if a['name']=='$ASSET_NAME'),''))")"
  [ -n "$OLD_ASSET_ID" ] && gh_api -X DELETE "https://api.github.com/repos/$FORK_REPO/releases/assets/$OLD_ASSET_ID" >/dev/null || true
fi

log "Uploading $ASSET_NAME ($(du -h "$SLUG_OUT" | cut -f1))"
curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
  -H "Content-Type: application/gzip" \
  --data-binary @"$SLUG_OUT" \
  "https://uploads.github.com/repos/$FORK_REPO/releases/$REL_ID/assets?name=$ASSET_NAME" >/dev/null
log "asset live at $ASSET_URL"

# ── Step 5: point Scalingo at the new slug and redeploy ───────────────────────
export SCALINGO_REGION
if [ -n "${SCALINGO_API_TOKEN:-}" ]; then
  log "Logging in to Scalingo via API token"
  scalingo login --api-token "$SCALINGO_API_TOKEN" >/dev/null
fi

log "Setting AP_SLUG_URL on $SCALINGO_APP"
scalingo --app "$SCALINGO_APP" env-set "AP_SLUG_URL=$ASSET_URL" >/dev/null

# The deploy source is a tiny archive whose only job is to carry the Procfile;
# the custom buildpack fetches AP_SLUG_URL at build time. Scalingo requires the
# source to sit inside a top-level subfolder (master/), or it silently drops it.
log "Triggering Scalingo redeploy"
DEPLOY_SRC="$(mktemp -d)/master"
mkdir -p "$DEPLOY_SRC"
cat > "$DEPLOY_SRC/Procfile" <<'PROC'
web: AP_CONTAINER_TYPE=APP bash run.sh
worker: AP_CONTAINER_TYPE=WORKER bash run.sh
PROC
DEPLOY_TGZ="$(dirname "$DEPLOY_SRC")/deploy.tar.gz"
tar -C "$(dirname "$DEPLOY_SRC")" -czf "$DEPLOY_TGZ" master
scalingo --app "$SCALINGO_APP" deploy "$DEPLOY_TGZ" "artha-${TARGET_VERSION}-$(date +%s)"

# ── Step 6: verify live ───────────────────────────────────────────────────────
log "Verifying live app at $LIVE_URL"
ok=0
for i in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$LIVE_URL" || true)"
  if [ "$code" = "200" ] && curl -s "$LIVE_URL" | grep -qF "$EXPECTED_TITLE"; then
    ok=1; break
  fi
  sleep 10
done
[ "$ok" -eq 1 ] || die "post-deploy verification failed: $LIVE_URL did not return HTTP 200 with the Artha title."
log "live: HTTP 200 + '$EXPECTED_TITLE' present."

# ── Step 7: record the new version ────────────────────────────────────────────
echo "$TARGET_VERSION" > "$VERSION_FILE"
log "DONE. Artha Automations updated $CURRENT_VERSION -> $TARGET_VERSION and live."
log "Commit deploy/artha/VERSION ($TARGET_VERSION) to record the deployed version."
