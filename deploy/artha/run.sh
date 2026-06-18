#!/usr/bin/env bash
# Slug launcher. Scalingo runs this for both the web (APP) and worker process
# types via the Procfile. node/bin holds node + pm2-runtime (+ bun, added by the
# buildpack); app/node_modules/.bin holds pnpm/esbuild, which the worker spawns
# by bare name when installing custom pieces.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HERE/node/bin:$HERE/app/node_modules/.bin:$PATH"
export AP_PORT="${PORT:-3000}"
export AP_CONTAINER_TYPE="${AP_CONTAINER_TYPE:-WORKER_AND_APP}"
export AP_PM2_INSTANCES="${AP_PM2_INSTANCES:-1}"
cd "$HERE/app"
exec sh docker-entrypoint.sh
