import { parseAllDocuments } from "yaml";
import { existsSync } from "node:fs";

export interface AppManifest {
  /** metadata.name of the Deployment */
  name: string;
  /** Full image string from the manifest, e.g. local/web-analytics:abc1234 */
  image: string;
  /** Image name without tag, e.g. local/web-analytics */
  imageBase: string;
  /** containerPort of the first container */
  port: number;
  /** claimName of the first PVC volume, if any */
  pvcName?: string;
  /** Raw YAML string of the entire manifest */
  raw: string;
}

/**
 * Find deployment.yaml by convention:
 *   1. <cwd>/deployment.yaml
 *   2. <cwd>/k8s/deployment.yaml
 */
export function findManifestPath(cwd: string = process.cwd()): string {
  const candidates = [
    `${cwd}/deployment.yaml`,
    `${cwd}/k8s/deployment.yaml`,
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  throw new Error(
    `No deployment.yaml found in ${cwd} or ${cwd}/k8s/. ` +
    "Run infra commands from an app directory that has a deployment.yaml."
  );
}

export async function loadManifest(cwd: string = process.cwd()): Promise<AppManifest> {
  const path = findManifestPath(cwd);
  const raw  = await Bun.file(path).text();
  return parseManifest(raw);
}

export function parseManifest(raw: string): AppManifest {
  const docs = parseAllDocuments(raw)
    .map(d => d.toJS() as Record<string, unknown>)
    .filter(Boolean);

  const deployment = docs.find(d => d?.kind === "Deployment");
  if (!deployment) throw new Error("No Deployment resource found in deployment.yaml");

  const spec      = deployment.spec as Record<string, unknown>;
  const podSpec   = ((spec.template as Record<string, unknown>).spec) as Record<string, unknown>;
  const containers = podSpec.containers as Array<Record<string, unknown>>;
  const container = containers[0];

  const image     = container.image as string;
  const imageBase = image.includes(":") ? image.split(":")[0] : image;
  const ports     = (container.ports as Array<Record<string, unknown>> | undefined) ?? [];
  const port      = (ports[0]?.containerPort as number) ?? 3000;

  const volumes   = (podSpec.volumes as Array<Record<string, unknown>> | undefined) ?? [];
  const pvcVol    = volumes.find(v => v.persistentVolumeClaim);
  const pvcName   = (pvcVol?.persistentVolumeClaim as Record<string, unknown> | undefined)
    ?.claimName as string | undefined;

  const meta = deployment.metadata as Record<string, unknown>;

  return {
    name:      meta.name as string,
    image,
    imageBase,
    port,
    pvcName,
    raw,
  };
}

/**
 * Replace the image tag in the raw manifest string and return the updated YAML.
 * Uses the same approach as docker-build-k3s.sh — a targeted string replace.
 */
export function updateImageTag(raw: string, imageBase: string, tag: string): string {
  const escapedBase = imageBase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return raw.replace(
    new RegExp(`(${escapedBase}:)[a-zA-Z0-9._-]+`),
    `$1${tag}`
  );
}
