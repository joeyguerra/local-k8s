import {
  LIMA_INSTANCE,
  KUBE_CONTEXT,
  getLimaStatus,
  startLima,
  stopLima,
  waitForK3s,
  openShell,
} from "../lib/lima.ts";
import { mergeKubeconfig } from "../lib/kubeconfig.ts";
import { installLaunchDaemon } from "../lib/launchdaemon.ts";
import { kubectl } from "../lib/kubectl.ts";

import { dirname, resolve } from "node:path";

// process.argv[0] is the actual binary path on disk in both compiled and dev
// mode. import.meta.url and Bun.main both resolve into /$bunfs/root/ when
// compiled, making them unusable for locating sibling files on disk.
const REPO_ROOT       = dirname(resolve(process.argv[0]));
const LIMA_YAML       = resolve(REPO_ROOT, "k3s-lima.yaml");
const NAMESPACES_DIR  = resolve(REPO_ROOT, "namespaces");
const RBAC_DIR        = resolve(REPO_ROOT, "rbac");

export async function run(subcommand: string, _args: string[]): Promise<void> {
  switch (subcommand) {
    case "setup":   return setup();
    case "start":   return start();
    case "stop":    return stop();
    case "status":  return status();
    case "shell":   return openShell(LIMA_INSTANCE);
    case "rbac":    return applyRbac();
    default:
      console.error(`Unknown subcommand: infra cluster ${subcommand ?? ""}`);
      console.error("Available: setup | start | stop | status | shell | rbac");
      process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// infra cluster setup — one-time initialization
// Mirrors setup-k3s.sh step by step.
// ---------------------------------------------------------------------------

async function setup(): Promise<void> {
  console.log("=== infra cluster setup ===\n");

  // 1. Prerequisites
  await ensureBrew();
  await ensureTool("limactl", "lima");
  await ensureTool("kubectl", "kubectl");

  // 2. Create the Lima VM (skip if it already exists)
  const existing = await getLimaStatus(LIMA_INSTANCE);
  if (existing === "NotFound") {
    console.log(`\n[lima] Creating VM "${LIMA_INSTANCE}" from ${LIMA_YAML}`);
    await Bun.$`limactl create --name=${LIMA_INSTANCE} ${LIMA_YAML}`;
  } else {
    console.log(`[lima] VM "${LIMA_INSTANCE}" already exists (${existing}) — skipping create`);
  }

  // 3. Start and wait
  await startLima(LIMA_INSTANCE);
  await waitForK3s(KUBE_CONTEXT);

  // 4. Merge kubeconfig
  await mergeKubeconfig(LIMA_INSTANCE, KUBE_CONTEXT);

  // 5. Apply namespace policies (PodSecurity labels, etc.)
  await applyNamespaces();

  // 6. Apply cluster-wide RBAC
  await applyRbac();

  // 6. Install LaunchDaemon so k3s starts at every boot
  await installLaunchDaemon();

  console.log("\n=== Setup complete ===");
  console.log(`Cluster context: ${KUBE_CONTEXT}`);
  console.log("Run:  kubectl --context=k3s-local get nodes");
  console.log("Next: infra cf setup    (deploy Cloudflare tunnel)");
}

// ---------------------------------------------------------------------------
// infra cluster start — used manually and replicated by start-lima-k3s.sh
// ---------------------------------------------------------------------------

async function start(): Promise<void> {
  await startLima(LIMA_INSTANCE);
  await waitForK3s(KUBE_CONTEXT);
  await mergeKubeconfig(LIMA_INSTANCE, KUBE_CONTEXT);
  console.log("[cluster] Ready");
}

// ---------------------------------------------------------------------------
// infra cluster stop
// ---------------------------------------------------------------------------

async function stop(): Promise<void> {
  await stopLima(LIMA_INSTANCE);
}

// ---------------------------------------------------------------------------
// infra cluster status
// ---------------------------------------------------------------------------

async function status(): Promise<void> {
  console.log("=== Lima VM ===");
  await Bun.$`limactl list`;

  const vmStatus = await getLimaStatus(LIMA_INSTANCE);
  if (vmStatus !== "Running") {
    console.log(`\n[k3s] VM is ${vmStatus} — cluster not accessible`);
    return;
  }

  const kc = kubectl(KUBE_CONTEXT, "default");
  console.log("\n=== Nodes ===");
  await kc.getNodes();

  console.log("\n=== Pods (all namespaces) ===");
  await kc.getAllPods();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// infra cluster rbac — apply cluster-wide RBAC manifests from rbac/
// ---------------------------------------------------------------------------

async function applyNamespaces(): Promise<void> {
  console.log("[namespaces] Applying namespace policies from namespaces/...");
  await Bun.$`kubectl --context=${KUBE_CONTEXT} apply -f ${NAMESPACES_DIR}`;
  console.log("[namespaces] Done");
}

async function applyRbac(): Promise<void> {
  console.log("[rbac] Applying cluster-wide RBAC from rbac/...");
  await Bun.$`kubectl --context=${KUBE_CONTEXT} apply -f ${RBAC_DIR}`;
  console.log("[rbac] Done");
}

async function ensureBrew(): Promise<void> {
  const r = await Bun.$`which brew`.quiet().nothrow();
  if (r.exitCode !== 0) {
    throw new Error("Homebrew is not installed. Install it from https://brew.sh then re-run.");
  }
}

async function ensureTool(bin: string, brewName: string): Promise<void> {
  const r = await Bun.$`which ${bin}`.quiet().nothrow();
  if (r.exitCode === 0) {
    console.log(`[deps] ${bin} ✓`);
    return;
  }
  console.log(`[deps] Installing ${brewName} via Homebrew...`);
  await Bun.$`brew install ${brewName}`;
}
