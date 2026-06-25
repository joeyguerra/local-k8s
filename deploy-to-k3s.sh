#!/usr/bin/env bash
# deploy-to-k3s.sh
#
# One-time migration script: deploys all apps from k3d to Lima k3s.
# Run this after setup-k3s.sh has completed.
#
# What it does:
#   1. Creates a fake 'k3d' shim on PATH so existing app build scripts
#      (docker-build-k3d.sh, docker-build.sh) import images into k3s
#      instead of k3d — no changes to app repos required.
#   2. Applies the Cloudflare tunnel secret and deployment.
#   3. Prompts for any other secrets not already present in k3s.
#   4. Runs 'npm run push' for each app with the k3s context.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBE_CONTEXT="k3s-local"
LIMA_INSTANCE="k3s"

log()  { echo "▶ $*"; }
warn() { echo "⚠ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

export KUBE_CONTEXT
export KUBE_CLUSTER="$LIMA_INSTANCE"  # used by app build scripts for the -c flag

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! kubectl --context="$KUBE_CONTEXT" get nodes &>/dev/null 2>&1; then
  fail "Cannot reach k3s. Is the Lima VM running? Try: limactl list"
fi

log "Connected to k3s cluster:"
kubectl --context="$KUBE_CONTEXT" get nodes
echo ""

# ── Fake k3d shim ─────────────────────────────────────────────────────────────
# App build scripts call: k3d image import <image> -c <cluster>
# The shim intercepts this and imports into Lima k3s instead.
# Any other k3d sub-commands (cluster, registry, etc.) are ignored safely.

SHIM_DIR=$(mktemp -d /tmp/k3d-shim-XXXXXX)
trap 'rm -rf "$SHIM_DIR"' EXIT

cat > "$SHIM_DIR/k3d" << 'SHIM'
#!/usr/bin/env bash
# Fake k3d: only handles 'k3d image import <image> -c <cluster>'
if [[ "${1:-}" == "image" && "${2:-}" == "import" ]]; then
  IMAGE="${3:-}"
  if [ -z "$IMAGE" ]; then
    echo "k3d-shim: no image specified" >&2
    exit 1
  fi
  LIMA_INSTANCE="${LIMA_INSTANCE:-k3s}"
  echo "k3d-shim: importing $IMAGE → Lima k3s ($LIMA_INSTANCE)"
  docker save "$IMAGE" | limactl shell "$LIMA_INSTANCE" -- sudo k3s ctr images import -
  echo "k3d-shim: ✓ $IMAGE imported"
  exit 0
fi
# Any other k3d command: log and succeed silently so scripts don't break
echo "k3d-shim: ignoring: k3d $*" >&2
exit 0
SHIM
chmod +x "$SHIM_DIR/k3d"
export PATH="$SHIM_DIR:$PATH"

log "k3d shim installed — image imports will go to Lima k3s."
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
  "../joeyguerra/lis7s"
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

  if npm install && npm run push; then
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
log "=== Migration complete ==="
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
echo ""
log "Once confirmed, you can remove k3d:"
echo "  k3d cluster delete local"
echo "  brew uninstall k3d"
