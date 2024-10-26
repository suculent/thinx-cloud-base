#!/bin/bash

# expected usage:
# ./update.sh --owner suculent

export TAG="alpine"
export OWNER="thinxcloud"

echo "Will update image with tag ${TAG}"

rm -rf ./node_modules/
rm -rf ./package-lock.json
npm install . --only-prod && npm audit fix

docker buildx build --platform=linux/amd64 -t $OWNER/base:alpine .

docker push $OWNER/base:alpine
