# https://github.com/chainguard-dev/kaniko/blob/main/deploy/Dockerfile

ARG GO_VERSION=1.25

FROM golang:$GO_VERSION AS builder
ARG REPO
ARG VERSION

ENV CGO_ENABLED=0
ENV GOBIN=/usr/local/bin

SHELL ["/usr/bin/bash", "-c"]
RUN set -x \
  \
  && git clone  --depth 1 -b $VERSION https://github.com/$REPO /src \
  && cd /src \
  && make \
    out/executor \
  \
  && TARGETARCH=$(arch) \
  && TARGETARCH=${TARGETARCH/x86_64/amd64} && TARGETARCH=${TARGETARCH/aarch64/arm64} \
  && JQ_VERSION=$(wget -O - https://api.github.com/repos/jqlang/jq/releases/latest | grep tag_name | cut -d '"' -f 4 | tr -d 'v') \
  && wget -O out/jq https://github.com/jqlang/jq/releases/download/$JQ_VERSION/jq-linux-$TARGETARCH \
  && chmod +x out/jq

# Generate latest ca-certificates
FROM debian:bookworm-slim AS certs
RUN apt update && apt install -y ca-certificates

# use musl busybox since it's staticly compiled on all platforms
FROM busybox:musl AS busybox

FROM scratch

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=busybox /bin /busybox
COPY --from=builder /src/out/jq /busybox/
COPY --from=builder /src/files/nsswitch.conf /etc/
COPY --from=builder /src/out/executor /kaniko/

ENV HOME=/root
ENV USER=root
ENV PATH=/usr/local/bin:/kaniko:/busybox
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG=/kaniko/.docker/
WORKDIR /workspace
VOLUME /busybox

RUN ["/busybox/mkdir", "-p", "/bin"]
RUN ["/busybox/ln", "-s", "/busybox/sh", "/bin/sh"]