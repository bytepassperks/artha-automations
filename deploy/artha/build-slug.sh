#!/usr/bin/env bash
# Build an Artha-branded Activepieces deploy slug from the upstream Docker image.
#
# The slug is a tarball whose root contains app/, node/ and run.sh. The Scalingo
# buildpack (bytepassperks/scalingo-buildpack-artha-automations) fetches it from
# AP_SLUG_URL and extracts it straight into the build dir.
#
# Usage: build-slug.sh <activepieces-version> [output-tarball]
set -euo pipefail

AP_VERSION="${1:?usage: build-slug.sh <activepieces-version> [output-tarball]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-$HERE/dist/ap-slug.tar.gz}"

IMAGE="ghcr.io/activepieces/activepieces:${AP_VERSION}"
REBRAND_IMAGE="artha-automations:${AP_VERSION}"

echo "==> pulling upstream image ${IMAGE}"
docker pull "$IMAGE"

echo "==> building rebranded image ${REBRAND_IMAGE}"
docker build -f "$HERE/Dockerfile" --build-arg "AP_VERSION=${AP_VERSION}" -t "$REBRAND_IMAGE" "$HERE"

WORKDIR="$(mktemp -d)"
SLUG="$WORKDIR/slug"
CID="$(docker create "$REBRAND_IMAGE")"
cleanup() { docker rm -f "$CID" >/dev/null 2>&1 || true; rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> extracting app + node runtime from image"
mkdir -p "$SLUG/app" "$SLUG/node/bin" "$SLUG/node/lib/node_modules"
docker cp "$CID:/usr/src/app/." "$SLUG/app/"
docker cp "$CID:/usr/local/bin/node" "$SLUG/node/bin/node"
docker cp "$CID:/usr/local/lib/node_modules/pm2" "$SLUG/node/lib/node_modules/pm2"
ln -sf ../lib/node_modules/pm2/bin/pm2-runtime "$SLUG/node/bin/pm2-runtime"

cp "$HERE/run.sh" "$SLUG/run.sh"
chmod +x "$SLUG/run.sh" "$SLUG/node/bin/node"

echo "==> archiving slug -> ${OUT}"
mkdir -p "$(dirname "$OUT")"
tar -C "$SLUG" -czf "$OUT" app node run.sh

echo "==> done: ${OUT} ($(du -h "$OUT" | cut -f1))"
echo "    upload this as the AP_SLUG_URL release asset, then redeploy Scalingo."
