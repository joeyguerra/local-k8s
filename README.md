# Local Kubernetes on Mac Mini (k3s via Lima)

Runs k3s inside a Lima VM on a Mac Mini, with public traffic via Cloudflare tunnel.
k3s auto-starts at boot via a LaunchDaemon — survives power outages without requiring login.

kubectl context: `k3s-local`

## Migrating from k3d → k3s (one-time)

### 1. Run setup (installs Lima, creates k3s VM, installs LaunchDaemon)

```sh
bash setup-k3s.sh
```

This installs Lima via Homebrew, creates a QEMU-backed Ubuntu VM running k3s,
merges `k3s-local` into `~/.kube/config`, and installs the boot LaunchDaemon.

### 2. Create `.env` with your Cloudflare tunnel token

```sh
echo "CF_TOKEN=your_token_here" > .env
```

Get the token from Cloudflare Zero Trust → Tunnels → your tunnel → Configure → Token.

### 3. Deploy all apps to k3s

```sh
bash deploy-to-k3s.sh
```

This deploys cloudflared, prompts for secrets (discord-token, cookie-secret),
and runs `npm run push` for each app. Existing app build scripts work unchanged —
a `k3d` shim intercepts image imports and redirects them to Lima k3s.

### 4. Verify, then decommission k3d

```sh
kubectl --context=k3s-local get pods -A

# Once confirmed everything is working:
k3d cluster delete local
brew uninstall k3d
```

---

## Day-to-day operations

### Check cluster status

```sh
kubectl --context=k3s-local get nodes
kubectl --context=k3s-local get pods -A
```

### Deploy an app update

From the app repo, same as before but with the new context:

```sh
KUBE_CONTEXT=k3s-local KUBE_CLUSTER=k3s npm run push
```

### Import a Docker image manually

```sh
./k3s-image-import.sh local/my-image:1.2.3
```

### Access the Lima VM

```sh
limactl shell k3s
```

### View LaunchDaemon boot log

```sh
tail -f /var/log/lima-k3s.log
```

### Stop / start Lima VM manually

```sh
limactl stop k3s
limactl start k3s --tty=false
```

### Reload the LaunchDaemon (after editing the plist)

```sh
sudo launchctl bootout system /Library/LaunchDaemons/com.joeyguerra.lima-k3s.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.joeyguerra.lima-k3s.plist
```

---

## Architecture

```
Mac Mini boot
  └── launchd (system)
        └── com.joeyguerra.lima-k3s (LaunchDaemon, runs as joeyguerra)
              └── start-lima-k3s.sh
                    └── limactl start k3s  ← QEMU VM
                          └── Ubuntu 24.04
                                └── k3s (systemd service)
                                      ├── cloudflared (2 replicas) → Cloudflare edge
                                      ├── jbot-website
                                      ├── coppellfornewtech-website
                                      ├── logprojector-website
                                      ├── lis7s-website
                                      └── fieldmappings-website
```

Port 6443 (k3s API) is forwarded from the VM to `127.0.0.1:6443` on the host.

---

## k3d reference (legacy)

The original k3d setup is preserved here for reference.

### Create a k3d cluster

```sh
k3d cluster create local-canary --k3s-arg="--disable=traefik@server:0" --image rancher/k3s
```

### Delete a k3d cluster

```sh
k3d cluster delete local
```

### Deploy apps to k3d

```sh
kubectl create secret generic cloudflared-token --from-env-file=.env -n default
kubectl apply -f cloudflared-deployment.yml
kubectl create secret generic discord-token --from-literal=HUBOT_DISCORD_TOKEN='<value>' -n default
kubectl create secret generic cookie-secret --from-literal=COOKIE_SECRET='<value>' -n default
KUBE_CONTEXT=k3d-local KUBE_CLUSTER=local ./deploy-all-apps.sh
```