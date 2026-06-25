#!/usr/bin/env bash
# k3s-image-import.sh
#
# Imports a local Docker image into the Lima k3s VM's containerd.
# Drop-in replacement for: k3d image import <image> -c <cluster>
#
# Usage: ./k3s-image-import.sh <image:tag>
# Example: ./k3s-image-import.sh local/jbot-website:3.0.81

set -euo pipefail

LIMA_INSTANCE="${LIMA_INSTANCE:-k3s}"

if [ $# -eq 0 ]; then
  echo "Usage: $0 <image:tag>" >&2
  exit 1
fi

IMAGE="$1"

echo "Importing $IMAGE into Lima k3s (containerd)..."
docker save "$IMAGE" | limactl shell "$LIMA_INSTANCE" -- sudo k3s ctr images import -
echo "✓ $IMAGE imported."
