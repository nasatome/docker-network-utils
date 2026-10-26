# Pinned by digest, not just by tag: a tag can be re-pointed (in March 2026
# malicious Trivy images were published under new tags on Docker Hub). The
# digest is the same on docker.io/aquasec/trivy and ghcr.io/aquasecurity/trivy.
# To update: pick a release that has been out for a few days with no advisory
# against it, compare its digest on both registries, and replace both parts.
FROM aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c
RUN apk add --no-cache jq curl tzdata
ENTRYPOINT []
