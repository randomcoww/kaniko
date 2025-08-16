# https://github.com/chainguard-dev/kaniko/blob/main/deploy/Dockerfile

ARG GO_VERSION=1.25

FROM golang:$GO_VERSION AS builder
ARG VERSION

ENV CGO_ENABLED=0
ENV GOBIN=/usr/local/bin

RUN set -x \
  \
  && git clone  --depth 1 -b $VERSION https://github.com/chainguard-dev/kaniko /src \
  && cd /src \
  && go install \
    github.com/GoogleCloudPlatform/docker-credential-gcr/v2 \
    github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login \
    github.com/chrismellard/docker-credential-acr-env \
  && make \
    out/executor \
    out/warmer

# Generate latest ca-certificates
FROM debian:bookworm-slim AS certs
RUN apt update && apt install -y ca-certificates

# use musl busybox since it's staticly compiled on all platforms
FROM busybox:musl AS busybox

FROM scratch

COPY --from=busybox /bin /busybox
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=builder /src/files/nsswitch.conf /etc/
COPY --from=builder /src/out/executor /kaniko/
COPY --from=builder /src/out/warmer /kaniko/
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-gcr /kaniko/
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-ecr-login /kaniko/
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-acr-env /kaniko/

ENV HOME=/root
ENV USER=root
ENV PATH=/usr/local/bin:/kaniko:/busybox
ENV SSL_CERT_DIR=/kaniko/ssl/certs
# ENV DOCKER_CONFIG=/kaniko/.docker/
# ENV DOCKER_CREDENTIAL_GCR_CONFIG=/kaniko/.config/gcloud/docker_credential_gcr_config.json
WORKDIR /workspace
VOLUME /busybox

RUN ["/busybox/mkdir", "-p", "/bin"]
RUN ["/busybox/ln", "-s", "/busybox/sh", "/bin/sh"]

RUN set -x \
  \
  && chmod 777 /kaniko \
  && mkdir -p /kaniko/.docker