# Copyright 2023 The OWASP Coraza contributors
# SPDX-License-Identifier: Apache-2.0

FROM --platform=$BUILDPLATFORM golang:1.19-alpine3.17 AS builder

WORKDIR /build
COPY . /build

# Download dependencies for all platforms once
RUN go mod download

ARG TARGETOS
ARG TARGETARCH
ARG CORERULESET_VERSION=v4.0.0-rc1
ARG CORERULESET_SHA256SUM=a8f0d1cac941bf2158988b92a91519f093a8bce64a260e46fa352d608c7de3e6

RUN apk add --no-cache make ca-certificates \
    && update-ca-certificates

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    OS=${TARGETOS} ARCH=${TARGETARCH} make

RUN wget -O /tmp/crs.tgz https://github.com/coreruleset/coreruleset/archive/refs/tags/${CORERULESET_VERSION}.tar.gz \
    && echo "$CORERULESET_SHA256SUM  /tmp/crs.tgz" | sha256sum -c \
    && mkdir crs \
    && tar --strip-components 1 -C crs -xf /tmp/crs.tgz

# ---
FROM alpine:3.17 AS main

ARG TARGETARCH

LABEL org.opencontainers.image.authors="The OWASP Coraza contributors" \
      org.opencontainers.image.description="OWASP Coraza WAF (Haproxy SPOA)" \
      org.opencontainers.image.documentation="https://coraza.io/connectors/coraza-spoa/" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/corazawaf/coraza-spoa" \
      org.opencontainers.image.title="coraza-spoa"

RUN apk add --no-cache tini socat ca-certificates \
    && update-ca-certificates

# Add unprivileged user & group for the coraza-spoa
RUN addgroup --system coraza-spoa \
    && adduser --system --ingroup coraza-spoa --no-create-home --home /nonexistent --disabled-password coraza-spoa

RUN mkdir -p /etc/coraza-spoa /var/log/coraza-spoa \
    && chown coraza-spoa:coraza-spoa /var/log/coraza-spoa

COPY --from=builder /build/coraza-spoa_${TARGETARCH} /usr/bin/coraza-spoa
COPY --from=builder /build/config.yaml.default /etc/coraza-spoa/config.yaml
COPY --from=builder /build/docker/coraza-spoa/coraza.conf /etc/coraza-spoa/coraza.conf
COPY --from=builder /build/docker/coraza-spoa/docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=builder /build/crs/crs-setup.conf.example /etc/coraza-spoa/crs-setup.conf
COPY --from=builder /build/crs/rules /etc/coraza-spoa/rules/
COPY --from=builder /build/crs/plugins /etc/coraza-spoa/plugins/

EXPOSE 9000
USER coraza-spoa

HEALTHCHECK --interval=10s --timeout=2s --retries=2 CMD "/usr/bin/socat /dev/null TCP:0.0.0.0:9000"

ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]

CMD ["/usr/bin/coraza-spoa", "--config", "/etc/coraza-spoa/config.yaml"]
