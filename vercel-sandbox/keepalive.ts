import { config } from "dotenv";
config({ path: ".env.local" });

import { Sandbox } from "@vercel/sandbox";
import { readFileSync, writeFileSync, existsSync } from "fs";

const FIVE_HOURS = 5 * 60 * 60 * 1000;
const FOUR_AND_HALF_HOURS = 4.5 * 60 * 60 * 1000;
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
    timeout: FIVE_HOURS,
  });
  console.log(`Sandbox created: ${sandbox.sandboxId}`);

  console.log("Pulling latest code...");
  await sandbox.runCommand("bash", [
    "-c",
    'cd ~/.proactive-engineer && git pull --quiet origin main 2>/dev/null || true',
  ]);

  console.log("Starting gateway...");
  await sandbox.runCommand("bash", [
    "-c",
    [
      'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.proactive-engineer/scripts/bin:$PATH"',
      "nohup openclaw --profile pe-default gateway --port 18789 > /tmp/openclaw-pe-default.log 2>&1 &",
      "disown",
    ].join(" && "),
  ]);

  console.log("Waiting for gateway to start...");
  await new Promise((r) => setTimeout(r, 10000));

  const check = await sandbox.runCommand("bash", [
    "-c",
    "tail -5 /tmp/openclaw-pe-default.log 2>/dev/null || echo 'No logs yet'",
  ]);
  console.log(await check.stdout());

  console.log(
    `Agent running. Will snapshot in ${FOUR_AND_HALF_HOURS / 1000 / 60 / 60} hours...`
  );
  await new Promise((r) => setTimeout(r, FOUR_AND_HALF_HOURS));

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
