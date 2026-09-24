FROM golang:1.26.8-alpine3.24 AS docker-cli

RUN apk add --no-cache ca-certificates curl git
WORKDIR /src/docker-cli

# Docker CLI v29.8.1, pinned by source commit and archive checksum.
RUN curl -fSL https://codeload.github.com/docker/cli/tar.gz/477f1252f2391a2b34fdce2e7bd03a0eee660005 -o /tmp/cli.tar.gz \
    && echo "4609135885a5afea23961dc07bb070febe3a9976165ff104b3138d46757006f8  /tmp/cli.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/cli.tar.gz --strip-components=1 \
    && rm /tmp/cli.tar.gz

# Upstream uses vendor.mod instead of go.mod. Build in module mode so the
# requested versions replace the vendored dependencies and remain auditable.
RUN cp vendor.mod go.mod && cp vendor.sum go.sum \
    && go get golang.org/x/net@v0.59.0 google.golang.org/grpc@v1.85.0-dev.0.20260825072537-93e31b48545e \
    && CGO_ENABLED=0 go build -mod=mod -trimpath -tags grpcnotrace \
       -ldflags "-s -w -X github.com/docker/cli/cli/version.Version=29.8.1 -X github.com/docker/cli/cli/version.GitCommit=477f125-deps" \
       -o /out/docker ./cmd/docker \
    && go version -m /out/docker | awk '\
       $1 == "dep" && $2 == "golang.org/x/net" { net = ($3 == "v0.59.0") } \
       $1 == "dep" && $2 == "google.golang.org/grpc" { grpc = ($3 == "v1.85.0-dev.0.20260825072537-93e31b48545e") } \
       END { exit !(net && grpc) }' \
    && /out/docker --version \
    && /out/docker run --help >/dev/null \
    && /out/docker service create --help >/dev/null

FROM dhi.io/node:26-alpine3.24-dev

LABEL maintainer="Matej Sychra <suculent@me.com>"
LABEL name="THiNX Base" version="2.0.3512"

# RUN adduser --system --disabled-password --shell /bin/bash thinx

# Packages

RUN apk add --update --no-cache openssh-client git jq zip curl bash ca-certificates openssl \
    && apk add --no-cache 'libexpat>=2.8.5-r0' \
    && apk list -I libexpat

# Use the host Docker socket; only the rebuilt CLI belongs in this image.
COPY --from=docker-cli /out/docker /usr/bin/docker

VOLUME /var/lib/docker

# Node.js app

WORKDIR /opt/thinx/thinx-device-api

# App dependencies

COPY ./package.json ./
COPY .snyk ./.snyk

# USER 1000:1000