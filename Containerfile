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
  && mkdir -p $GOBIN \
  && git clone  --depth 1 -b $VERSION https://github.com/chainguard-dev/kaniko kaniko \
  && cd kaniko \
  && go install \
    github.com/GoogleCloudPlatform/docker-credential-gcr/v2 \
    github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login \
    github.com/chrismellard/docker-credential-acr-env \
  && make \
    out/executor \
    out/warmer \
  && mv out/executor $GOBIN/ \
  && mv out/warmer $GOBIN/

# use musl busybox since it's staticly compiled on all platforms
FROM busybox:musl AS busybox

FROM scratch

COPY --from=busybox /bin /busybox
COPY --from=builder /usr/local/bin /kaniko
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /kaniko/ssl/certs/
COPY --from=builder /src/kaniko/files/nsswitch.conf /etc/

ENV PATH=/usr/local/bin:/kaniko:/busybox
ENV HOME=/root
ENV USER=root
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG=/kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG=/kaniko/.config/gcloud/docker_credential_gcr_config.json
WORKDIR /workspace
VOLUME /busybox

RUN ["/busybox/mkdir", "-p", "/bin"]
RUN ["/busybox/ln", "-s", "/busybox/sh", "/bin/sh"]