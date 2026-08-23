import { existsSync, writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PLIST_NAME = "com.joeyguerra.lima-k3s";
const PLIST_DEST = `/Library/LaunchDaemons/${PLIST_NAME}.plist`;

// Embedded at compile time so the binary is self-contained
import PLIST_CONTENT from "../../com.joeyguerra.lima-k3s.plist" with { type: "text" };

/**
 * Install the LaunchDaemon plist and load it via launchctl.
 *
 * Requires sudo — the script prompts macOS for credentials automatically
 * when running in a terminal. Mirrors the steps in setup-k3s.sh.
 *
 * Safe to re-run: if the plist is already loaded it first unloads it,
 * then re-installs and re-loads.
 */
export async function installLaunchDaemon(): Promise<void> {
  console.log(`[launchdaemon] Installing ${PLIST_NAME} (requires sudo)...`);

  // Write embedded plist to a temp file so we can sudo cp it
  const tmp = join(tmpdir(), `${PLIST_NAME}.plist`);
  writeFileSync(tmp, PLIST_CONTENT, "utf8");

  try {
    // Unload first if it's already installed, so we can overwrite cleanly
    if (existsSync(PLIST_DEST)) {
      await Bun.$`sudo launchctl bootout system/${PLIST_NAME}`.nothrow();
    }

    await Bun.$`sudo cp ${tmp} ${PLIST_DEST}`;
    await Bun.$`sudo launchctl bootstrap system ${PLIST_DEST}`;
  } finally {
    unlinkSync(tmp);
  }

  console.log(`[launchdaemon] ${PLIST_NAME} installed and loaded — will auto-start at boot`);
}
