import { parse } from "yaml";
import { existsSync } from "node:fs";

export interface Values {
  context: string;
  namespace: string;
  lima: string;
  backup: {
    db: string;       // path to SQLite file inside the container
    hostPath: string; // host directory to write backups into
  };
}

const DEFAULTS: Values = {
  context: "k3s-local",
  namespace: "default",
  lima: "k3s",
  backup: { db: "", hostPath: "" },
};

/**
 * Load values.yaml and values.local.yaml from `dir`, deep-merge them over
 * the built-in defaults, and return a fully-resolved Values object.
 *
 * values.local.yaml is gitignored and takes precedence over values.yaml.
 */
export async function loadValues(dir: string = process.cwd()): Promise<Values> {
  let base: Partial<Values> = {};
  let local: Partial<Values> = {};

  const basePath  = `${dir}/values.yaml`;
  const localPath = `${dir}/values.local.yaml`;

  if (existsSync(basePath)) {
    const raw = await Bun.file(basePath).text();
    base = (parse(raw) as Partial<Values>) ?? {};
  }

  if (existsSync(localPath)) {
    const raw = await Bun.file(localPath).text();
    local = (parse(raw) as Partial<Values>) ?? {};
  }

  return deepMerge(deepMerge(DEFAULTS, base), local) as Values;
}

function deepMerge(target: Record<string, unknown>, source: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...target };
  for (const key of Object.keys(source)) {
    const sv = source[key];
    const tv = target[key];
    if (sv && typeof sv === "object" && !Array.isArray(sv) &&
        tv && typeof tv === "object" && !Array.isArray(tv)) {
      out[key] = deepMerge(
        tv as Record<string, unknown>,
        sv as Record<string, unknown>
      );
    } else if (sv !== undefined) {
      out[key] = sv;
    }
  }
  return out;
}
