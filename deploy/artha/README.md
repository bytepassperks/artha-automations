# Artha Automations — white-label deploy layer

This directory is the **entire** Artha rebrand of Activepieces. It is a thin
overlay applied to the pristine upstream Docker image at build time — it does
**not** modify any upstream source file. That isolation is what lets the fork
track upstream releases and auto-merge cleanly (upstream changes can never
conflict with files only Artha owns).

## Contents

| File | Purpose |
|---|---|
| `rebrand.sh` | Applies the Artha brand (name, colour, logos, links, emails) to an extracted Activepieces build tree. Idempotent; preserves `cdn.activepieces.com` (the working piece/badge icon CDN). |
| `Dockerfile` | `FROM ghcr.io/activepieces/activepieces:<version>` + runs `rebrand.sh`. Produces the branded image. |
| `build-slug.sh` | Builds the branded image and extracts `app/` + `node/` + `run.sh` into the Scalingo deploy slug tarball. |
| `run.sh` | Slug launcher used by the Scalingo Procfile for both `web` and `worker`. |
| `update.sh` | Auto-update entrypoint: bump version → rebuild slug → publish release → repoint Scalingo → redeploy. |
| `assets/` | Artha brand image files baked into the web root. |

## Build + deploy a new version

```sh
# 1. Build the branded slug from an Activepieces version
./build-slug.sh 0.80.1

# 2. Publish dist/ap-slug.tar.gz as the release asset referenced by AP_SLUG_URL
#    and trigger a Scalingo redeploy (see update.sh for the automated path).
```

## How auto-update works

`update.sh <version>` performs the full cycle non-interactively: it fast-forwards
`main` to the upstream tag, rebuilds the slug, uploads it to a GitHub release,
points the Scalingo `AP_SLUG_URL` env var at the new asset, and triggers a
redeploy. A scheduled job runs it whenever Activepieces publishes a new release.
Because the rebrand never touches upstream source, the version bump is the only
change and it merges without conflict.
