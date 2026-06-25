#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
KUBE_CONTEXT="${KUBE_CONTEXT:-k3s-local}"
LIMA_INSTANCE="${LIMA_INSTANCE:-k3s}"

# ── Cloudflare tunnel ─────────────────────────────────────────────────────────

ENV_FILE="$ROOT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found. Create it with: echo 'CF_TOKEN=your_token' > $ROOT_DIR/.env" >&2
    exit 1
fi

kubectl --context="$KUBE_CONTEXT" create secret generic cloudflared-token \
    --from-env-file="$ENV_FILE" -n default \
    --dry-run=client -o yaml \
    | kubectl --context="$KUBE_CONTEXT" apply -f -

echo "Importing cloudflare/cloudflared image into k3s..."
docker pull cloudflare/cloudflared:latest
docker save cloudflare/cloudflared:latest \
    | limactl shell "$LIMA_INSTANCE" -- sudo k3s ctr images import -

kubectl --context="$KUBE_CONTEXT" apply -f "$ROOT_DIR/cloudflared-deployment.yml"
echo "cloudflared deployed."

# ── Apps ──────────────────────────────────────────────────────────────────────

# List each app directory relative to this repo root
apps=(
	"../devchitchat/chat"
    "../joeyguerra/coppellfornewtech"
    "../fieldmappings/website"
    "../joeyguerra/joeyguerra"
    "../joeyguerra/lis7s"
	"../logprojector/website"
	"../devchitchat/oplog"
)

if [ ${#apps[@]} -eq 0 ]; then
	echo 'No app directories configured in deploy-all-apps.sh' >&2
	exit 1
fi

for app in "${apps[@]}"; do
	app_path="$ROOT_DIR/$app"
	if [ ! -d "$app_path" ]; then
		echo "Skipping $app because $app_path does not exist" >&2
		continue
	fi

	echo "Installing dependencies and deploying $app"
	pushd "$app_path" >/dev/null

	if [ -f bun.lock ] || [ -f bun.lockb ]; then
		PKG=bun
	else
		PKG=npm
	fi

	$PKG install
	KUBE_CONTEXT="$KUBE_CONTEXT" \
	KUBE_CLUSTER="${KUBE_CLUSTER:-k3s}" \
	LIMA_INSTANCE="$LIMA_INSTANCE" \
	$PKG run push
	popd >/dev/null
done
