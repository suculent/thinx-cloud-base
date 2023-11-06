FROM node:21-alpine3.18

LABEL maintainer="Matej Sychra <suculent@me.com>"
LABEL name="THiNX Base" version="1.9.2429"

# RUN adduser --system --disabled-password --shell /bin/bash thinx

# Packages

RUN apk add --update --no-cache openssh-client git jq zip curl

ENV VER="20.10.21"
RUN curl -sL -o /tmp/docker-$VER.tgz https://download.docker.com/linux/static/stable/x86_64/docker-$VER.tgz && \
    tar -xz -C /tmp -f /tmp/docker-$VER.tgz && \
    rm -rf /tmp/docker-$VER.tgz && \
    mv /tmp/docker/* /usr/bin

VOLUME /var/lib/docker

# Node.js app

WORKDIR /opt/thinx/thinx-device-api

# App dependencies

COPY ./package.json ./
COPY .snyk ./.snyk

# USER 1000:1000