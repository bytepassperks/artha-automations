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

# ── 3. Privacy / terms links ──────────────────────────────────────────────────
sed -i \
  -e "s|https://www.activepieces.com/privacy|${PRIVACY_URL}|g" \
  -e "s|https://www.activepieces.com/terms|${TERMS_URL}|g" \
  "$FLAGS/flag.service.js"

# ── 4. Frontend HTML — page title and favicon links ──────────────────────────
sed -i \
  -e "s|<title>Activepieces</title>|<title>${BRAND_NAME}</title>|g" \
  -e "s|href=\"https://activepieces.com/favicon.ico\"|href=\"/favicon.ico\"|g" \
  "$WEB/index.html"

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
