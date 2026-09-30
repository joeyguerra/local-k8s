# local-k8s

VM and cluster management for a Mac Mini running k3s via Lima, with GitOps deployments via the mesh stack.

## What's here

```
vm/k3s-lima.yaml               Lima VM definition (QEMU, Ubuntu, k3s)
vm/registries.yaml             k3s insecure registry mirror config (registry.local:5000)
bootstrap-mesh.sh               One-time GitOps stack bootstrap
namespaces/                     Namespace PodSecurity policies
cloudflared-deployment.yml      Cloudflare tunnel manifest (embedded by infra cf setup)
vm/com.joeyguerra.lima-k3s.plist   LaunchDaemon — starts Lima VM at boot (no login required)
vm/start-lima-k3s.sh           Called by the LaunchDaemon

cicd/
  mesh-ci-runner/               mesh daemon + bun + docker CLI — runs CI pipelines
  mesh-gitops-controller/       polls mesh-gitops repo and applies manifests to k3s

src/                            infra CLI source (TypeScript / Bun)
cli.ts                          CLI entry point
```

## Architecture

```
Mac Mini boot
  └── launchd → com.joeyguerra.lima-k3s (LaunchDaemon, no login required)
        └── limactl start k3s  (QEMU VM, Ubuntu 24.04)
              └── k3s
                    ├── mesh-system/
                    │     ├── registry          in-cluster image registry (NodePort 30500)
                    │     └── mesh-gitops-controller  polls mesh-gitops.git every 30s
                    ├── ci/
                    │     └── mesh-ci-runner    mesh daemon + CI runner (builds + pushes images)
                    └── default/
                          ├── cloudflared       → Cloudflare edge (public traffic)
                          └── ... apps          managed by GitOps
```

**Deployments go through GitOps.** Push a manifest change to the `mesh-gitops` repo and the controller applies it within 30s. Images are built by the CI runner when commits land on the mesh network.

**Mesh P2P network** (kaizen-hq/mesh v5.4.1) connects the host, ci-runner, controller, and agent. Each node serves git repos over self-signed HTTPS at port 7979.

## First-time setup

### 1. Create the VM and install the LaunchDaemon

```sh
infra cluster setup
```

This installs Lima, creates the k3s VM, merges the kubeconfig, applies namespace policies, and installs the boot LaunchDaemon.

### 2. Copy `.env.example` → `.env` and fill in your mesh pubkey

```sh
cp .env.example .env
# Edit .env: set MESH_PEER_PUBKEY to the output of: mesh pubkey
```

### 3. Bootstrap the GitOps stack

```sh
infra cluster bootstrap
```

This builds and pushes the mesh-ci-runner and mesh-gitops-controller images, deploys the in-cluster registry, runs the invite/join dance, and pushes the gitops repo into the mesh network.

### 4. Deploy the Cloudflare tunnel

```sh
infra cf setup
```

Reads `CF_TOKEN` from `~/.config/infra/.env` (or `CF_TOKEN` env var).

## Day-to-day

```sh
infra cluster status     # VM status, nodes, GitOps stack, all pods
infra cluster start      # start Lima VM + wait for k3s API
infra cluster stop       # gracefully stop Lima VM
infra cluster shell      # interactive shell inside the Lima VM
```

kubectl context: `k3s-local`

## Security: host home directory

Lima mounts `~` into the VM by default and this cannot be disabled ([lima#627](https://github.com/lima-vm/lima/discussions/627)). `namespaces/default.yaml` enforces the `baseline` PodSecurity profile on the `default` namespace, which blocks `hostPath` volumes at the API server level.

## Mesh peering topology

```
host (joey-agent, host.lima.internal:7979)
  └── mesh-ci-runner (ci namespace, mesh-ci-runner.ci.svc.cluster.local:7979)
        ├── mesh-gitops-controller (mesh-system)
        └── agent (default)
```

Peering is established once via `mesh invite` / `mesh join` and persists in PVCs at `/home/mesh/.mesh`. Re-run `infra cluster bootstrap` after a full teardown.

## Redeploying infrastructure images

The CI runner and GitOps controller are not self-managed by GitOps — they are the infrastructure that runs GitOps. To update them, build and push from the Mac host, then force a rollout so k3s pulls the new image.

```sh
# Rebuild and push
docker build -t host.docker.internal:5050/mesh-ci-runner:latest ./cicd/mesh-ci-runner
docker push host.docker.internal:5050/mesh-ci-runner:latest

docker build -t host.docker.internal:5050/mesh-gitops-controller:latest ./cicd/mesh-gitops-controller
docker push host.docker.internal:5050/mesh-gitops-controller:latest

# Force new pods (k3s will pull the updated image)
kubectl rollout restart deployment/mesh-ci-runner -n ci
kubectl rollout restart deployment/mesh-gitops-controller -n mesh-system
```

`host.docker.internal:5050` is the Mac-side entry point for the in-cluster registry — Docker in Colima reaches it via the Lima port forward. The k3s node pulls the same image via the `registry.local:5000` mirror (NodePort 30500).

## Deploying the agent

The agent is not part of the bootstrap — deploy it separately once the GitOps stack is running:

```sh
cd ../devchitchat/agent
./deploy.sh
```

This builds and pushes the agent and mesh-agent images, pushes `apps/agent/deployment.yaml` into the gitops repo, waits for rollout, and peers the agent's mesh node with the CI runner.
