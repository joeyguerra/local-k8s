#!/usr/bin/env bash
# deploy-to-k3s.sh
#
# Deploys all apps to Lima k3s. Run this after setup-k3s.sh has completed.
#
# What it does:
#   1. Applies the Cloudflare tunnel secret and deployment.
#   2. Prompts for any other secrets not already present in k3s.
#   3. Runs 'npm run push' for each app with the k3s context.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_CONTEXT="k3s-local"
LIMA_INSTANCE="k3s"

log()  { echo "▶ $*"; }
warn() { echo "⚠ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

export KUBE_CONTEXT

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! kubectl --context="$KUBE_CONTEXT" get nodes &>/dev/null 2>&1; then
  fail "Cannot reach k3s. Is the Lima VM running? Try: limactl list"
fi

log "Connected to k3s cluster:"
kubectl --context="$KUBE_CONTEXT" get nodes
echo ""

# ── Cloudflare tunnel ─────────────────────────────────────────────────────────

log "Setting up Cloudflare tunnel..."

ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  warn ".env not found at $SCRIPT_DIR/.env"
  warn "Create it with: echo 'CF_TOKEN=your_token_here' > $SCRIPT_DIR/.env"
  warn "Get your token from: Cloudflare Zero Trust → Tunnels → your tunnel → Configure → Token"
  echo ""
  read -rp "Press Enter to continue without the CF token (cloudflared will not connect), or Ctrl+C to abort: "
else
  kubectl --context="$KUBE_CONTEXT" create secret generic cloudflared-token \
    --from-env-file="$ENV_FILE" -n default \
    --dry-run=client -o yaml \
    | kubectl --context="$KUBE_CONTEXT" apply -f -
  log "cloudflared-token secret applied."
fi

log "Pulling cloudflare/cloudflared image into k3s..."
docker pull cloudflare/cloudflared:latest
docker save cloudflare/cloudflared:latest \
  | limactl shell "$LIMA_INSTANCE" -- sudo k3s ctr images import -

kubectl --context="$KUBE_CONTEXT" apply -f "$SCRIPT_DIR/cloudflared-deployment.yml"
log "cloudflared deployment applied."
echo ""

# ── App secrets ───────────────────────────────────────────────────────────────
# These are referenced by deployment.yaml files but must be created manually
# since the values are sensitive. We only create them if they don't already exist.

create_secret_if_missing() {
  local secret_name="$1"
  local prompt="$2"
  local literal_key="$3"

  if kubectl --context="$KUBE_CONTEXT" get secret "$secret_name" -n default &>/dev/null 2>&1; then
    log "Secret '$secret_name' already exists — skipping."
    return
  fi

  warn "Secret '$secret_name' not found."
  read -rsp "  Enter value for $prompt (input hidden): " SECRET_VALUE
  echo ""
  kubectl --context="$KUBE_CONTEXT" create secret generic "$secret_name" \
    --from-literal="$literal_key=$SECRET_VALUE" -n default
  log "Secret '$secret_name' created."
}

log "Checking app secrets..."
create_secret_if_missing "discord-token"    "HUBOT_DISCORD_TOKEN" "HUBOT_DISCORD_TOKEN"
create_secret_if_missing "cookie-secret"    "COOKIE_SECRET"       "COOKIE_SECRET"
echo ""

# ── Deploy apps ───────────────────────────────────────────────────────────────

ROOT_DIR="$SCRIPT_DIR"

apps=(
	"../devchitchat/chat"
  "../joeyguerra/coppellfornewtech"
  "../fieldmappings/website"
  "../joeyguerra/joeyguerra"
  "../joeyguerra/joey-agent"
  "../joeyguerra/lis7s"
  "../joeyguerra/invoices"
	"../logprojector/website"
	"../devchitchat/oplog"
)

FAILED=()

for app in "${apps[@]}"; do
  app_path="$ROOT_DIR/$app"
  if [ ! -d "$app_path" ]; then
    warn "Skipping $app — directory not found at $app_path"
    continue
  fi

  log "Deploying $app..."
  pushd "$app_path" >/dev/null

  if [ -f bun.lock ] || [ -f bun.lockb ]; then PKG=bun; else PKG=npm; fi
  if $PKG install && $PKG run push; then
    log "✓ $app deployed."
  else
    warn "✗ $app failed — continuing with remaining apps."
    FAILED+=("$app")
  fi

  popd >/dev/null
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
log "=== Deploy complete ==="
echo ""

if [ ${#FAILED[@]} -gt 0 ]; then
  warn "These apps failed and need attention:"
  for f in "${FAILED[@]}"; do
    echo "    - $f"
  done
  echo ""
fi

log "Verify everything is running:"
echo "  kubectl --context=$KUBE_CONTEXT get pods -A"
