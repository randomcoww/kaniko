# https://github.com/chainguard-dev/kaniko/blob/main/deploy/Dockerfile

ARG GO_VERSION=1.25

FROM golang:$GO_VERSION AS builder
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
  && mkdir -p /kaniko \
  && chmod 777 /kaniko \
  && git clone  --depth 1 -b $VERSION https://github.com/chainguard-dev/kaniko kaniko \
  && cd kaniko \
  && make out/executor out/warmer \
  && mv out/executor /kaniko \
  && mv out/warmer /kaniko \
  && go install \
    github.com/GoogleCloudPlatform/docker-credential-gcr/v2 \
    github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login \
    github.com/chrismellard/docker-credential-acr-env

# use musl busybox since it's staticly compiled on all platforms
FROM busybox:musl AS busybox

FROM scratch

COPY --from=busybox /bin /bin/
COPY --from=builder /kaniko /
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=builder /src/kaniko/files/nsswitch.conf /etc/
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-gcr /kaniko/docker-credential-gcr
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-ecr-login /kaniko/docker-credential-ecr-login
COPY --from=builder --chown=0:0 /usr/local/bin/docker-credential-acr-env /kaniko/docker-credential-acr-env

ENV PATH=/bin:/kaniko
ENV HOME=/root
ENV USER=root
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG=/kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG=/kaniko/.config/gcloud/docker_credential_gcr_config.json
WORKDIR /workspace

RUN set -x \
  \
  && mkdir -p $DOCKER_CONFIG