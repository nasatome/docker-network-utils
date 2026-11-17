# Pinned by digest, not just by tag: a tag can be re-pointed (in March 2026
# malicious Trivy images were published under new tags on Docker Hub). The
# digest is the same on docker.io/aquasec/trivy and ghcr.io/aquasecurity/trivy.
# To update: pick a release that has been out for a few days with no advisory
# against it, compare its digest on both registries, and replace both parts.
FROM aquasec/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb
RUN apk add --no-cache jq curl tzdata
ENTRYPOINT []
