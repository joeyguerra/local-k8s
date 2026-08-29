#!/usr/bin/env bun
export {};

const [, , cmd, sub, ...rest] = process.argv;

switch (cmd) {
  case "cluster": {
    const { run } = await import("./src/commands/cluster.ts");
    await run(sub, rest);
    break;
  }
  case "cf": {
    const { run } = await import("./src/commands/cloudflare.ts");
    await run(sub, rest);
    break;
  }
  case "push":
  case "build":
  case "up":
  case "render":
  case "status":
  case "logs":
  case "backup": {
    const { run } = await import("./src/commands/app.ts");
    await run(cmd, rest);
    break;
  }
  default:
    help();
    process.exit(cmd ? 1 : 0);
}

function help(): void {
  console.log(`
infra — k3s cluster and app deployment CLI

Cluster:
  infra cluster setup    one-time cluster initialization (brew, lima, k3s, launchdaemon)
  infra cluster start    start Lima VM + wait for k3s API
  infra cluster stop     gracefully stop Lima VM
  infra cluster status   show VM status, nodes, and all pods
  infra cluster shell    open an interactive shell inside the Lima VM
  infra cluster rbac     apply cluster-wide RBAC manifests from rbac/

Cloudflare:
  infra cf setup         deploy cloudflared tunnel to the cluster

App  (run from an app directory that has a deployment.yaml):
  infra push             build image → import to k3s → apply manifest
  infra build            docker build + k3s import only
  infra up               kubectl apply only (no build)
  infra render           print the final manifest to stdout
  infra status           kubectl get pods for this app
  infra logs             tail logs for this app
  infra backup           backup the SQLite DB to the host path in values.yaml

Convention:
  deployment.yaml        standard K8s manifest — source of truth
  infra.yaml             CLI config (context, namespace, lima, backup)
  infra.local.yaml       local overrides (gitignored, deep-merged over infra.yaml)
`);
}
