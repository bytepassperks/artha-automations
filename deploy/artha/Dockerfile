# Artha Automations build image: pristine Activepieces + the Artha white-label
# layer. Used only to produce the deploy slug (see build-slug.sh); it is never
# run as a container on Scalingo (Scalingo is buildpack-only).
ARG AP_VERSION=0.80.1
FROM ghcr.io/activepieces/activepieces:${AP_VERSION}

# Allow the realtime socket to fall back to long-polling behind proxies that do
# not support raw websocket upgrades.
RUN sed -i "s/transports: \['websocket'\]/transports: ['websocket', 'polling']/" \
    packages/server/api/dist/src/app/server.js || true

COPY assets/ /tmp/artha-assets/
COPY rebrand.sh /tmp/rebrand.sh
RUN sh /tmp/rebrand.sh /usr/src/app /tmp/artha-assets \
    && rm -rf /tmp/rebrand.sh /tmp/artha-assets
