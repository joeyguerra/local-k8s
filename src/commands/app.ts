import { loadManifest, updateImageTag } from "../lib/manifest.ts";
import { loadValues } from "../lib/values.ts";
import { resolveTag, buildImage, importToK3s } from "../lib/docker.ts";
import { kubectl } from "../lib/kubectl.ts";
import { mkdirSync } from "node:fs";

export async function run(command: string, _args: string[]): Promise<void> {
  switch (command) {
    case "push":   return push();
    case "build":  return build();
    case "up":     return up();
    case "render": return render();
    case "status": return appStatus();
    case "logs":   return logs();
    case "backup": return backup();
    default:
      console.error(`Unknown command: infra ${command}`);
      process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Shared: load manifest + values from the current working directory
// ---------------------------------------------------------------------------

async function loadContext() {
  const cwd    = process.cwd();
  const values = await loadValues(cwd);
  const app    = await loadManifest(cwd, values.vars);
  const kc     = kubectl(values.context, values.namespace);
  return { cwd, values, app, kc };
}

// ---------------------------------------------------------------------------
// infra push — build image → import to k3s → apply manifest
// ---------------------------------------------------------------------------

async function push(): Promise<void> {
  const { app, values, kc } = await loadContext();

  const tag     = await resolveTag(app.imageBase, app.raw);
  const updated = updateImageTag(app.raw, app.imageBase, tag);

  await buildImage(app.imageBase, tag);
  await importToK3s(app.imageBase, tag, values.lima);

  // Write the tag-updated manifest back to wherever it was loaded from
  // (deployment.yaml or k8s/deployment.yaml) so the file stays in sync.
  await Bun.write(app.manifestPath, updated);

  await kc.apply(updated);

  // Always restart — even if the manifest was unchanged, a new image was
  // imported under the same tag and Kubernetes won't pull it automatically.
  console.log(`[push] Restarting deployment/${app.name}...`);
  await kc.rolloutRestart(app.name);

  console.log(`\n[push] ${app.name} deployed (${app.imageBase}:${tag})`);
}

// ---------------------------------------------------------------------------
// infra build — docker build + k3s import only (no kubectl apply)
// ---------------------------------------------------------------------------

async function build(): Promise<void> {
  const { app, values } = await loadContext();
  const tag = await resolveTag(app.imageBase, app.raw);
  await buildImage(app.imageBase, tag);
  await importToK3s(app.imageBase, tag, values.lima);
}

// ---------------------------------------------------------------------------
// infra up — apply current manifest (no build)
// ---------------------------------------------------------------------------

async function up(): Promise<void> {
  const { app, kc } = await loadContext();
  await kc.apply(app.raw);
  console.log(`[up] Applied manifest for ${app.name}`);
}

// ---------------------------------------------------------------------------
// infra render — print the final manifest to stdout
// ---------------------------------------------------------------------------

async function render(): Promise<void> {
  const { app } = await loadContext();
  console.log(app.raw);
}

// ---------------------------------------------------------------------------
// infra status — kubectl get pods for this app
// ---------------------------------------------------------------------------

async function appStatus(): Promise<void> {
  const { app, kc } = await loadContext();
  await kc.getPods(app.name);
}

// ---------------------------------------------------------------------------
// infra logs — tail the last 100 lines and follow
// ---------------------------------------------------------------------------

async function logs(): Promise<void> {
  const { app, kc } = await loadContext();
  await kc.logs(app.name);
}

// ---------------------------------------------------------------------------
// infra backup — copy the SQLite DB out of the running pod
//
// Convention (from values.yaml):
//   backup.db       path to the .db file inside the container
//   backup.hostPath host directory to write the backup file into
//
// Uses kubectl cp — best-effort for WAL-mode SQLite (safe between writes,
// not a fully atomic snapshot). Good enough for a personal project; swap
// in a sqlite3 .backup call if stricter consistency is needed.
// ---------------------------------------------------------------------------

async function backup(): Promise<void> {
  const { app, values, kc } = await loadContext();

  const { db: dbPath, hostPath } = values.backup;

  if (!dbPath) {
    console.error('[backup] backup.db is not set in values.yaml');
    console.error('Example:\n  backup:\n    db: /var/lib/analytics/analytics.db');
    process.exit(1);
  }
  if (!hostPath) {
    console.error('[backup] backup.hostPath is not set in values.yaml (or values.local.yaml)');
    console.error('Example:\n  backup:\n    hostPath: /Users/you/backups/my-app');
    process.exit(1);
  }

  mkdirSync(hostPath, { recursive: true });

  const pod = await kc.getPodName(app.name);
  if (!pod) throw new Error(`No running pod found for app=${app.name}`);

  const ts   = new Date().toISOString().replace(/[:.]/g, "-");
  const dest = `${hostPath}/${app.name}-${ts}.db`;

  console.log(`[backup] ${pod}:${dbPath} → ${dest}`);
  await kc.cp(pod, dbPath, dest);

  // Also grab the WAL file if it exists (zero harm if it doesn't)
  await kc.cp(pod, `${dbPath}-wal`, `${dest}-wal`).catch(() => {});

  console.log(`[backup] Done → ${dest}`);
}
