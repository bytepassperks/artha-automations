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
| `update.sh` | Auto-update entrypoint: resolve latest upstream → rebuild slug → publish release → repoint Scalingo → redeploy → verify. |
| `VERSION` | The upstream Activepieces version currently deployed. Single source of truth used by `update.sh` to decide whether an update is needed. |
| `assets/` | Artha brand image files baked into the web root. |

## Build + deploy a new version

```sh
# 1. Build the branded slug from an Activepieces version
./build-slug.sh 0.80.1

# 2. Publish dist/ap-slug.tar.gz as the release asset referenced by AP_SLUG_URL
#    and trigger a Scalingo redeploy (see update.sh for the automated path).
```

## How auto-update works

The deploy is a pristine upstream image + the `rebrand.sh` overlay, so an
"update" is just: point at a newer upstream version, rebuild the slug, re-apply
the overlay, redeploy. `update.sh` does the whole cycle non-interactively:

1. Resolve the latest **stable** upstream release (skips `-rc`/`-alpha`/`-beta`).
2. Stop if `VERSION` is already on it (unless `--force`).
3. Rebuild the slug `FROM` the upstream image at that version. `rebrand.sh`
   asserts every branded token (name, colour, logo/favicon URLs, privacy/terms
   links, web bundles) and the `Dockerfile` asserts the Socket.IO transport
   patch — **if upstream text drifted, the build fails loudly here** and nothing
   ships.
4. Publish the slug as the `deploy-<version>-artha` GitHub release asset.
5. Point Scalingo `AP_SLUG_URL` at it and trigger a redeploy.
6. Verify the live app returns HTTP 200 with the Artha `<title>`.
7. Bump `VERSION`.

```sh
export GH_TOKEN=...            # repo scope (release upload)
export SCALINGO_API_TOKEN=...  # headless Scalingo auth (or a logged-in CLI)

./update.sh --dry-run          # resolve + build + assert only; never touches prod
./update.sh                    # full update to latest stable
./update.sh 0.85.4             # update to a specific version
./update.sh --force            # rebuild/redeploy the current version
```

Because the rebrand never touches upstream source, a version bump can never
conflict with upstream. The only thing that can stop an update is a branding
assertion failing (upstream renamed/restyled something we rewrite) — that is a
loud build failure, not a silent half-branded deploy, and the fix is a one-line
update to `rebrand.sh`.

### Scheduling

A recurring Devin session runs `update.sh` on a cadence (same model as Artha's
other rebranded forks). On a clean run it ships the new version automatically;
on an assertion failure it surfaces the failed token so a human can patch
`rebrand.sh`. Run `./update.sh --dry-run` any time to check whether the current
upstream still rebrands cleanly without touching production.
