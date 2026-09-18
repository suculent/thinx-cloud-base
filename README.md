# thinx-cloud/base

This is a base container image for development, CI, building and running [THiNX](https://github.com/suculent/thinx-device-api.git)

**Base image:** this image builds on [Docker Hardened Images](https://dhi.io)
(`dhi.io/node:26-alpine3.24-dev`). `dhi.io` rejects anonymous pulls, so log in once
with your Docker Hub account before building — locally or in CI:

```
docker login dhi.io
```

The image includes Docker CLI 29.8.1 built from pinned, checksum-verified source
with `golang.org/x/net v0.59.0` and `google.golang.org/grpc v1.84.0`. Both versions
are checked in the compiled binary during the build. Applications must mount
`/var/run/docker.sock` to use the host Docker daemon; this image does not include
a Docker daemon, containerd, or runc.
