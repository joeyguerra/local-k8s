#!/usr/bin/env bash
# copy-secrets.sh
#
# Copies user-managed secrets from one cluster to another.
# Skips Helm release secrets and service account tokens.
#
# Usage: ./copy-secrets.sh [source-context] [dest-context]
# Defaults: k3d-local → k3s-local

set -euo pipefail

SRC="${1:-k3d-local}"
DST="${2:-k3s-local}"
NAMESPACE="${NAMESPACE:-default}"

echo "Copying secrets: $SRC → $DST (namespace: $NAMESPACE)"
echo ""

SKIP_TYPES=(
    "helm.sh/release.v1"
    "kubernetes.io/service-account-token"
)

secrets=$(kubectl --context="$SRC" get secrets -n "$NAMESPACE" -o json)

echo "$secrets" | jq -r '.items[] | @base64' | while read -r encoded; do
    secret=$(echo "$encoded" | base64 --decode)

    name=$(echo "$secret" | jq -r '.metadata.name')
    type=$(echo "$secret" | jq -r '.type')

    # Skip system-managed types
    skip=false
    for skip_type in "${SKIP_TYPES[@]}"; do
        if [ "$type" = "$skip_type" ]; then
            skip=true
            break
        fi
    done

    if $skip; then
        echo "  Skipping $name (type: $type)"
        continue
    fi

    # Strip cluster-specific metadata before applying
    clean=$(echo "$secret" | jq '
        del(
            .metadata.resourceVersion,
            .metadata.uid,
            .metadata.creationTimestamp,
            .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"
        )
    ')

    echo "  Copying $name (type: $type)..."
    echo "$clean" | kubectl --context="$DST" apply -f - -n "$NAMESPACE"
done

echo ""
echo "Done. Verify with:"
echo "  kubectl --context=$DST get secrets -n $NAMESPACE"
