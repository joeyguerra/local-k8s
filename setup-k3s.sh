#!/usr/bin/env bash
# setup-k3s.sh
#
# One-time setup: installs Lima, creates a k3s VM, merges the kubeconfig,
# and installs the LaunchDaemon so k3s starts at every boot — no login required.
#
# Run once:  bash setup-k3s.sh
# After this, everything is automatic on reboot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMA_INSTANCE="k3s"
KUBE_CONTEXT="k3s-local"
PLIST_NAME="com.joeyguerra.lima-k3s"
PLIST_SRC="$SCRIPT_DIR/$PLIST_NAME.plist"
PLIST_DST="/Library/LaunchDaemons/$PLIST_NAME.plist"
START_SCRIPT="$SCRIPT_DIR/start-lima-k3s.sh"

log()  { echo "▶ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

# ── 1. Prerequisites ─────────────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
  fail "Homebrew not found. Install it from https://brew.sh then re-run."
fi

log "Installing / upgrading Lima..."
brew install lima || brew upgrade lima

log "Installing kubectl (if needed)..."
brew install kubectl || true

# ── 2. Create Lima k3s VM ────────────────────────────────────────────────────

if limactl list "$LIMA_INSTANCE" &>/dev/null 2>&1; then
  log "Lima instance '$LIMA_INSTANCE' already exists — skipping create."
else
  log "Creating Lima VM '$LIMA_INSTANCE' from k3s-lima.yaml..."
  limactl create --name="$LIMA_INSTANCE" "$SCRIPT_DIR/k3s-lima.yaml"
fi

log "Starting Lima VM..."
limactl start "$LIMA_INSTANCE" --tty=false

# ── 3. Wait for k3s to be ready ──────────────────────────────────────────────

log "Waiting for k3s API server to be ready (this takes ~60s on first boot)..."
for i in $(seq 1 60); do
  if limactl shell "$LIMA_INSTANCE" -- sudo kubectl get nodes &>/dev/null 2>&1; then
    log "k3s is ready."
    break
  fi
  if [ "$i" -eq 60 ]; then
    fail "k3s did not become ready in 5 minutes. Check: limactl shell k3s -- journalctl -u k3s -n 50"
  fi
  printf "  waiting... (%d/60)\r" "$i"
  sleep 5
done

# ── 4. Merge kubeconfig ───────────────────────────────────────────────────────

log "Merging kubeconfig into ~/.kube/config with context '$KUBE_CONTEXT'..."
mkdir -p "$HOME/.kube"

GUEST_KUBECONFIG="$HOME/.lima/$LIMA_INSTANCE/copied-from-guest/k3s.yaml"
if [ ! -f "$GUEST_KUBECONFIG" ]; then
  # Fallback: copy directly from guest
  limactl shell "$LIMA_INSTANCE" -- sudo cat /etc/rancher/k3s/k3s.yaml > "$GUEST_KUBECONFIG"
fi

# Rename all "default" entries so they don't collide with other clusters
TMP_CFG=$(mktemp /tmp/k3s-lima-XXXXXX.yaml)
sed \
  -e "s/name: default/name: $KUBE_CONTEXT/g" \
  -e "s/cluster: default/cluster: $KUBE_CONTEXT/g" \
  -e "s/user: default/user: $KUBE_CONTEXT/g" \
  -e "s/current-context: default/current-context: $KUBE_CONTEXT/g" \
  "$GUEST_KUBECONFIG" > "$TMP_CFG"

if [ ! -f "$HOME/.kube/config" ]; then
  cp "$TMP_CFG" "$HOME/.kube/config"
else
  TMP_MERGED=$(mktemp /tmp/k3s-merged-XXXXXX.yaml)
  KUBECONFIG="$HOME/.kube/config:$TMP_CFG" kubectl config view --flatten > "$TMP_MERGED"
  mv "$TMP_MERGED" "$HOME/.kube/config"
fi
chmod 600 "$HOME/.kube/config"
rm -f "$TMP_CFG"

log "kubectl context '$KUBE_CONTEXT' is ready."
kubectl --context="$KUBE_CONTEXT" get nodes

# ── 5. Apply cluster-wide RBAC ───────────────────────────────────────────────

log "Applying cluster-wide RBAC from rbac/..."
kubectl --context="$KUBE_CONTEXT" apply -f "$SCRIPT_DIR/rbac/"

# ── 6. Install LaunchDaemon ───────────────────────────────────────────────────

log "Installing LaunchDaemon (requires sudo)..."
sudo cp "$PLIST_SRC" "$PLIST_DST"
sudo chown root:wheel "$PLIST_DST"
sudo chmod 644 "$PLIST_DST"
chmod +x "$START_SCRIPT"

# Unload first in case it was previously loaded
sudo launchctl bootout system "$PLIST_DST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST_DST"

log ""
log "✓ Setup complete."
log ""
log "  Lima VM:      limactl list"
log "  k3s context:  kubectl --context=$KUBE_CONTEXT get nodes"
log "  Daemon log:   tail -f /var/log/lima-k3s.log"
log ""
log "Next step: run ./deploy-to-k3s.sh to migrate your apps."
