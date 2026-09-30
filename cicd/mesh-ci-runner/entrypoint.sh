#!/bin/bash
set -e

git config --global http.https://localhost:7979.sslVerify false
git config --global http.https://host.lima.internal:7979.sslVerify false

if [ ! -f ~/.mesh/mesh.toml ]; then
  mesh init
  sed -i "s/^name = .*/name = \"${MESH_NODE_NAME:-ci-runner}\"/" ~/.mesh/mesh.toml
fi

# Always ensure shell mode is enabled and CI env vars are passed through (safe to re-apply on restart)
sed -i "s/^execution_modes = .*/execution_modes = [\"docker\", \"shell\"]/" ~/.mesh/mesh.toml
if grep -q '^env_passthrough' ~/.mesh/mesh.toml; then
  sed -i 's/^env_passthrough = .*/env_passthrough = ["REGISTRY_HOST", "GITOPS_REPO_URL", "DOCKER_HOST"]/' ~/.mesh/mesh.toml
else
  sed -i '/^\[runner\]/a env_passthrough = ["REGISTRY_HOST", "GITOPS_REPO_URL", "DOCKER_HOST"]' ~/.mesh/mesh.toml
fi

exec mesh start
