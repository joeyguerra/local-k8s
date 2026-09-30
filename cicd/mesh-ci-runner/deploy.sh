#!/bin/bash
set -euo pipefail

docker build -t host.docker.internal:5050/mesh-ci-runner:latest ./cicd/mesh-ci-runner
docker push host.docker.internal:5050/mesh-ci-runner:latest
kubectl rollout restart deployment/mesh-ci-runner -n ci
