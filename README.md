# thinx-cloud/base

This is a base container image for development, CI, building and running [THiNX](https://github.com/suculent/thinx-device-api.git)

**Base image:** this image builds on [Docker Hardened Images](https://dhi.io)
(`dhi.io/node:26-alpine3.24-dev`). `dhi.io` rejects anonymous pulls, so log in once
with your Docker Hub account before building — locally or in CI:

```
docker login dhi.io
```
