FROM alpine/curl:8.23.0@sha256:c8df739636f42117e358bdffb4c243c460b31cbba8cc69241a22ab519546f34d AS curl

ARG TINI_VERSION=v0.19.0
ARG TINI_SHA256=77cce5f4e61954b3420c4465197d8b826a4cf978eba016a9c5859eea0e4c0866
RUN curl -fsSLo /tini "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-muslc-amd64" \
 && echo "${TINI_SHA256}  /tini" | sha256sum -c - \
 && chmod 755 /tini

FROM quay.io/nginx/nginx-unprivileged:1.31.8-alpine3.24-perl@sha256:9dbda6544010221265cc1090f4e049f664646a3878765aef8acdf55715e2258c

USER root
RUN apk add --no-cache jq
# curl is dynamically linked: pin the binary and libcurl; its other libs come from the
# base image, which must stay on the same Alpine release as alpine/curl (3.24).
COPY --from=curl /usr/bin/curl /usr/bin/curl
COPY --from=curl /usr/lib/libcurl.so.4.8.0 /usr/lib/libcurl.so.4.8.0
COPY --from=curl /tini /sbin/tini
COPY scripts/fetch.sh /usr/local/bin/headscale-exporter.sh
COPY scripts/90-headscale-exporter.sh /docker-entrypoint.d/90-headscale-exporter.sh
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
USER 101

EXPOSE 8081

# tini as PID 1 reaps the refresh loop and any orphans; when nginx exits, tini exits and
# the kernel kills everything left in the container. Setting ENTRYPOINT clears the
# inherited CMD, so it is restated here.
ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
