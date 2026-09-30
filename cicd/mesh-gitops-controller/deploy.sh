#!/bin/bash
set -euo pipefail

docker build -t host.docker.internal:5050/mesh-gitops-controller:latest ./cicd/mesh-gitops-controller
docker push host.docker.internal:5050/mesh-gitops-controller:latest
kubectl rollout restart deployment/mesh-gitops-controller -n ci
