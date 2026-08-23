// Colima is the Docker backend. Use its socket so commands work without
// Docker Desktop. Override via the DOCKER_HOST environment variable.
const DOCKER_HOST =
  process.env.DOCKER_HOST ??
  `unix://${process.env.HOME}/.colima/default/docker.sock`;

/**
 * Determine the image tag to use for this build.
 *
 * Logic mirrors docker-build-k3s.sh:
 *   - Use the current git short SHA.
 *   - If the manifest already has that SHA as its tag (i.e. nothing changed
 *     in git since the last deploy), fall back to a Unix timestamp so k3s
 *     always sees a new image and re-pulls.
 */
export async function resolveTag(imageBase: string, manifestRaw: string): Promise<string> {
  const head = (await Bun.$`git rev-parse --short HEAD`.text()).trim();

  const escapedBase = imageBase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = manifestRaw.match(new RegExp(`${escapedBase}:([a-zA-Z0-9._-]+)`));
  const deployed = match?.[1];

  return head !== deployed ? head : String(Date.now());
}

/**
 * Build the Docker image and load it into the local Colima daemon.
 */
export async function buildImage(imageBase: string, tag: string): Promise<void> {
  const image = `${imageBase}:${tag}`;
  console.log(`[docker] Building ${image}`);
  await Bun.$`docker build --load -t ${image} .`
    .env({ ...process.env, DOCKER_HOST });
  console.log(`[docker] Build complete: ${image}`);
}

/**
 * Import a Docker image from the Colima daemon into k3s's containerd.
 * This is the local-registry-free approach: docker save | k3s ctr images import.
 */
export async function importToK3s(imageBase: string, tag: string, limaInstance: string): Promise<void> {
  const image = `${imageBase}:${tag}`;
  console.log(`[k3s] Importing ${image} into containerd...`);
  await Bun.$`docker save ${image} | limactl shell ${limaInstance} -- sudo k3s ctr images import -`
    .env({ ...process.env, DOCKER_HOST });
  console.log(`[k3s] Import complete`);
}

/**
 * Pull a public Docker image and import it into k3s.
 * Used for images like cloudflare/cloudflared that aren't built locally.
 */
export async function pullAndImport(image: string, limaInstance: string): Promise<void> {
  console.log(`[docker] Pulling ${image}...`);
  await Bun.$`docker pull ${image}`.env({ ...process.env, DOCKER_HOST });
  console.log(`[k3s] Importing ${image} into containerd...`);
  await Bun.$`docker save ${image} | limactl shell ${limaInstance} -- sudo k3s ctr images import -`
    .env({ ...process.env, DOCKER_HOST });
}
