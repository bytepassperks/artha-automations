#!/usr/bin/env sh
# Apply the Artha Automations white-label layer on top of a pristine Activepieces
# build tree. Idempotent: safe to run repeatedly; each replacement is a no-op once
# applied. Designed to run inside the upstream image at build time (WORKDIR
# /usr/src/app) but works on any extracted build tree.
#
# Usage: rebrand.sh <app-root> <assets-dir>
set -eu

APP_ROOT="${1:?usage: rebrand.sh <app-root> <assets-dir>}"
ASSETS_DIR="${2:?usage: rebrand.sh <app-root> <assets-dir>}"

# Post-condition guard: a sed no-match exits 0, so without this an upstream text
# drift would silently ship a half-branded slug. Asserting the *branded result*
# (not the source token) keeps the script idempotent: it passes on a fresh run
# and on a re-run. The first failed assertion aborts the build loudly.
assert_contains() {
  if ! grep -qF -- "$2" "$1"; then
    echo "rebrand: ASSERTION FAILED — expected '$2' in $1" >&2
    echo "rebrand: upstream text likely drifted; refusing to ship a half-branded build." >&2
    exit 1
  fi
}

# ── Brand configuration ──────────────────────────────────────────────────────
BRAND_NAME="Artha Automations"
PRIMARY_COLOR="#202870"
# Absolute base used only where a relative URL cannot resolve (email clients).
APP_BASE="https://artha-automations.osc-fr1.scalingo.io"
PRIVACY_URL="https://arthize.com/privacy-policy"
TERMS_URL="https://arthize.com/terms-of-service"

WEB="$APP_ROOT/dist/packages/web"
FLAGS="$APP_ROOT/packages/server/api/dist/src/app/flags"
EMAILS="$APP_ROOT/packages/server/api/src/assets/emails"

# In-app logos are referenced as root-relative URLs so the brand never hardcodes
# a deploy domain (keeps auto-updates domain-independent). Emails must use an
# absolute base because mail clients have no page origin to resolve against.
FULL_LOGO_REL="/artha-logo-full.png"
LOGO_ICON_REL="/artha-logo-icon.png"
FAVICON_REL="/artha-favicon.png"
EMAIL_LOGO_ABS="$APP_BASE/artha-logo-full.png"

# ── 1. Static brand files served from the web root ───────────────────────────
cp "$ASSETS_DIR/artha-logo-full.png" "$WEB/artha-logo-full.png"
cp "$ASSETS_DIR/artha-logo-icon.png" "$WEB/artha-logo-icon.png"
cp "$ASSETS_DIR/artha-favicon.png"   "$WEB/artha-favicon.png"
cp "$ASSETS_DIR/favicon.ico"         "$WEB/favicon.ico"
cp "$ASSETS_DIR/logo.svg"            "$WEB/logo.svg"
cp "$ASSETS_DIR/artha-logo-180.png"  "$WEB/logo-180.png"
cp "$ASSETS_DIR/artha-logo-192.png"  "$WEB/logo-192.png"

# ── 2. Backend default theme (drives title bar, login, sidebar, favicon) ──────
# Community Edition always renders the default theme, so the brand must live here
# rather than in the per-platform appearance settings.
sed -i \
  -e "s|websiteName: 'Activepieces'|websiteName: '${BRAND_NAME}'|g" \
  -e "s|primaryColor: '#6e41e2'|primaryColor: '${PRIMARY_COLOR}'|g" \
  -e "s|fullLogoUrl: 'https://cdn.activepieces.com/brand/full-logo.png'|fullLogoUrl: '${FULL_LOGO_REL}'|g" \
  -e "s|favIconUrl: 'https://cdn.activepieces.com/brand/logo.svg'|favIconUrl: '${FAVICON_REL}'|g" \
  -e "s|logoIconUrl: 'https://cdn.activepieces.com/brand/logo.svg'|logoIconUrl: '${LOGO_ICON_REL}'|g" \
  "$FLAGS/theme.js"
assert_contains "$FLAGS/theme.js" "websiteName: '${BRAND_NAME}'"
assert_contains "$FLAGS/theme.js" "primaryColor: '${PRIMARY_COLOR}'"
assert_contains "$FLAGS/theme.js" "fullLogoUrl: '${FULL_LOGO_REL}'"
assert_contains "$FLAGS/theme.js" "favIconUrl: '${FAVICON_REL}'"
assert_contains "$FLAGS/theme.js" "logoIconUrl: '${LOGO_ICON_REL}'"

# ── 3. Privacy / terms links ──────────────────────────────────────────────────
sed -i \
  -e "s|https://www.activepieces.com/privacy|${PRIVACY_URL}|g" \
  -e "s|https://www.activepieces.com/terms|${TERMS_URL}|g" \
  "$FLAGS/flag.service.js"
assert_contains "$FLAGS/flag.service.js" "${PRIVACY_URL}"
assert_contains "$FLAGS/flag.service.js" "${TERMS_URL}"

# ── 4. Frontend HTML — page title and favicon links ──────────────────────────
sed -i \
  -e "s|<title>Activepieces</title>|<title>${BRAND_NAME}</title>|g" \
  -e "s|href=\"https://activepieces.com/favicon.ico\"|href=\"/favicon.ico\"|g" \
  "$WEB/index.html"
assert_contains "$WEB/index.html" "<title>${BRAND_NAME}</title>"

# ── 5. Compiled frontend bundles — brand name only ───────────────────────────
# Only quoted string literals are replaced. A blanket replace would corrupt JS
# identifiers (e.g. extractActivepiecesRouteFromUrl, window.ActivepiecesEmbedded)
# because the brand name contains a space, which is illegal inside an identifier.
# Hostnames are deliberately left untouched so cdn.activepieces.com (piece/badge
# icons) and the upstream docs/help links keep working.
find "$WEB/assets" -name "*.js" -exec sed -i \
  -e "s|\"Activepieces\"|\"${BRAND_NAME}\"|g" \
  -e "s|'Activepieces'|'${BRAND_NAME}'|g" \
  {} +
# At least one bundle must carry the branded name, else the replace silently missed.
if ! grep -rqF -- "${BRAND_NAME}" "$WEB/assets"; then
  echo "rebrand: ASSERTION FAILED — '${BRAND_NAME}' not found in any web bundle under $WEB/assets" >&2
  exit 1
fi

# ── 6. Email templates ───────────────────────────────────────────────────────
if [ -d "$EMAILS" ]; then
  find "$EMAILS" -name "*.html" -exec sed -i \
    -e "s|https://cdn.activepieces.com/brand/full-logo.png|${EMAIL_LOGO_ABS}|g" \
    -e "s|https://cdn.activepieces.com/brand/logo.svg|${EMAIL_LOGO_ABS}|g" \
    -e "s|https://www.activepieces.com|https://arthize.com|g" \
    -e "s|Activepieces|${BRAND_NAME}|g" \
    {} +
fi

echo "rebrand: applied '${BRAND_NAME}' to ${APP_ROOT}"
