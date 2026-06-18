# Artha Automations build image: pristine Activepieces + the Artha white-label
# layer. Used only to produce the deploy slug (see build-slug.sh); it is never
# run as a container on Scalingo (Scalingo is buildpack-only).
ARG AP_VERSION=0.80.1
FROM ghcr.io/activepieces/activepieces:${AP_VERSION}

# Allow the realtime socket to fall back to long-polling behind proxies that do
# not support raw websocket upgrades. Fail the build if the upstream pattern has
# drifted rather than silently shipping a websocket-only build.
RUN SRV=packages/server/api/dist/src/app/server.js \
    && grep -q "transports: \['websocket'\]" "$SRV" \
    && sed -i "s/transports: \['websocket'\]/transports: ['websocket', 'polling']/" "$SRV" \
    && grep -q "transports: \['websocket', 'polling'\]" "$SRV"

COPY assets/ /tmp/artha-assets/
COPY rebrand.sh /tmp/rebrand.sh
RUN sh /tmp/rebrand.sh /usr/src/app /tmp/artha-assets \
    && rm -rf /tmp/rebrand.sh /tmp/artha-assets
