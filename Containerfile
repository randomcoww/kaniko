# https://github.com/chainguard-dev/kaniko/blob/main/deploy/Dockerfile

FROM golang:1.25 AS builder
WORKDIR /src

ARG VERSION

# This arg is passed by docker buildx & contains the target CPU architecture (e.g., amd64, arm64, etc.)
ARG TARGETARCH
ARG TARGETOS

ENV GOARCH=$TARGETARCH
ENV GOOS=$TARGETOS

ENV CGO_ENABLED=0
ENV GOBIN=/usr/local/bin

RUN set -x \
  \
  && mkdir -p /kaniko/.docker \
  && chmod 777 /kaniko \
  && git clone  --depth 1 -b $VERSION https://github.com/chainguard-dev/kaniko kaniko \
  && cd kaniko \
  && go install \
    github.com/GoogleCloudPlatform/docker-credential-gcr/v2 \
    github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login \
    github.com/chrismellard/docker-credential-acr-env \
  \
  && make out/executor out/warmer

# use musl busybox since it's staticly compiled on all platforms
FROM busybox:musl AS busybox

FROM scratch AS kaniko-base

COPY --from=builder /kaniko /
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=builder /src/kaniko/files/nsswitch.conf /etc/
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-gcr /kaniko/docker-credential-gcr
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-ecr-login /kaniko/docker-credential-ecr-login
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-acr-env /kaniko/docker-credential-acr-env

ENV HOME=/root
ENV USER=root
ENV PATH=/usr/local/bin:/kaniko
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG=/kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG=/kaniko/.config/gcloud/docker_credential_gcr_config.json
WORKDIR /workspace

### FINAL STAGES ###

FROM kaniko-base AS kaniko-debug

ENV PATH=/usr/local/bin:/kaniko:/busybox

COPY --from=builder /src/kaniko/out/warmer /kaniko/
COPY --from=builder /src/kaniko/out/executor /kaniko/

COPY --from=busybox /bin /busybox
# Declare /busybox as a volume to get it automatically in the path to ignore
VOLUME /busybox

RUN ["/busybox/mkdir", "-p", "/bin"]
RUN ["/busybox/ln", "-s", "/busybox/sh", "/bin/sh"]