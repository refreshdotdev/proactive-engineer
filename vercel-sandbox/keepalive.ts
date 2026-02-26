import { config } from "dotenv";
config({ path: ".env.local" });

import { Sandbox } from "@vercel/sandbox";
import { readFileSync, writeFileSync, existsSync } from "fs";

const SANDBOX_TIMEOUT = 45 * 60 * 1000; // 45 minutes (Hobby plan max)
const SNAPSHOT_BEFORE_TIMEOUT = 40 * 60 * 1000; // snapshot at 40 minutes
const STATE_FILE = ".sandbox-state.json";

function getSnapshotId(): string {
  if (process.env.SNAPSHOT_ID) return process.env.SNAPSHOT_ID;
  if (existsSync(STATE_FILE)) {
    const state = JSON.parse(readFileSync(STATE_FILE, "utf8"));
    if (state.snapshotId) return state.snapshotId;
  }
  throw new Error(
    "No snapshot ID found. Run `npm run deploy` first, or set SNAPSHOT_ID env var."
  );
}

function saveState(state: Record<string, string>) {
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

async function main() {
  const snapshotId = getSnapshotId();
  console.log(`Resuming from snapshot: ${snapshotId}`);

  const sandbox = await Sandbox.create({
    source: { type: "snapshot", snapshotId },
    timeout: SANDBOX_TIMEOUT,
  });
  console.log(`Sandbox created: ${sandbox.sandboxId}`);

  console.log("Pulling latest code...");
  await sandbox.runCommand("bash", [
    "-c",
    'cd ~/.proactive-engineer && git pull --quiet origin main 2>/dev/null || true',
  ]);

  console.log("Cleaning up stale state from snapshot...");
  await sandbox.runCommand("bash", [
    "-c",
    "pkill -f 'openclaw.*gateway' 2>/dev/null; sleep 1; rm -f /tmp/openclaw-1000/gateway.*.lock /tmp/openclaw-pe-default.log; rm -rf /tmp/openclaw",
  ]);

  console.log("Starting gateway...");
  await sandbox.runCommand("bash", [
    "-c",
    'export PATH="$HOME/.global/npm/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.proactive-engineer/scripts/bin:$PATH"; nohup openclaw --profile pe-default gateway --port 18789 > /tmp/openclaw-pe-default.log 2>&1 & disown',
  ]);

  console.log("Waiting for gateway to start...");
  await new Promise((r) => setTimeout(r, 15000));

  const check = await sandbox.runCommand("bash", [
    "-c",
    "cat /tmp/openclaw-pe-default.log 2>/dev/null || echo 'No logs yet'",
  ]);
  console.log(await check.stdout());

  console.log(
    `Agent running. Will snapshot in ${SNAPSHOT_BEFORE_TIMEOUT / 1000 / 60} minutes...`
  );
  await new Promise((r) => setTimeout(r, SNAPSHOT_BEFORE_TIMEOUT));

  console.log("Creating snapshot before timeout...");
  const newSnapshot = await sandbox.snapshot({ expiration: 0 });
  console.log(`New snapshot: ${newSnapshot.snapshotId}`);

  saveState({
    snapshotId: newSnapshot.snapshotId,
    previousSnapshotId: snapshotId,
    sandboxId: sandbox.sandboxId,
    updatedAt: new Date().toISOString(),
  });

  console.log("Snapshot saved. Sandbox will stop shortly.");
}

main().catch((err) => {
  console.error("Keepalive failed:", err);
  process.exit(1);
});
