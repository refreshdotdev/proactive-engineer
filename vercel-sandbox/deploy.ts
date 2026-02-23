import { config } from "dotenv";
config({ path: ".env.local" });

import { Sandbox } from "@vercel/sandbox";
import { writeFileSync, readFileSync, existsSync } from "fs";

const FIVE_HOURS = 5 * 60 * 60 * 1000;
const REPO = "https://github.com/refreshdotdev/proactive-engineer.git";
const STATE_FILE = ".sandbox-state.json";

function requireEnv(key: string): string {
  const val = process.env[key];
  if (!val) throw new Error(`Missing env var: ${key}. See .env.example`);
  return val;
}

function saveState(state: Record<string, string>) {
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  console.log(`State saved to ${STATE_FILE}`);
}

async function main() {
  const slackAppToken = requireEnv("SLACK_APP_TOKEN");
  const slackBotToken = requireEnv("SLACK_BOT_TOKEN");
  const geminiApiKey = requireEnv("GEMINI_API_KEY");
  const agentName = process.env.AGENT_NAME || "default";
  const agentDisplayName = process.env.AGENT_DISPLAY_NAME || "Proactive Engineer";

  const githubAppId = process.env.GITHUB_APP_ID || "";
  const githubAppInstallationId = process.env.GITHUB_APP_INSTALLATION_ID || "";
  const githubAppPem = process.env.GITHUB_APP_PEM || "";
  const githubToken = process.env.GITHUB_TOKEN || "";

  console.log("Creating sandbox...");
  const sandbox = await Sandbox.create({ timeout: FIVE_HOURS });
  console.log(`Sandbox created: ${sandbox.sandboxId}`);

  console.log("Installing OpenClaw...");
  await sandbox.runCommand("bash", [
    "-c",
    "curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard",
  ]);

  console.log("Cloning proactive-engineer...");
  await sandbox.runCommand("git", [
    "clone",
    "--depth",
    "1",
    REPO,
    "/home/user/.proactive-engineer",
  ]);

  console.log("Setting up skill symlink...");
  await sandbox.runCommand("bash", [
    "-c",
    "mkdir -p ~/.openclaw/skills && ln -sf ~/.proactive-engineer/skills/proactive-engineer ~/.openclaw/skills/proactive-engineer",
  ]);

  if (githubAppPem) {
    console.log("Writing GitHub App PEM...");
    await sandbox.runCommand("bash", [
      "-c",
      `cat > ~/.proactive-engineer/github-app.pem << 'PEMEOF'\n${githubAppPem}\nPEMEOF\nchmod 600 ~/.proactive-engineer/github-app.pem`,
    ]);
  }

  console.log("Running configure-agent.sh...");
  const envPrefix = [
    `SLACK_APP_TOKEN="${slackAppToken}"`,
    `SLACK_BOT_TOKEN="${slackBotToken}"`,
    `GEMINI_API_KEY="${geminiApiKey}"`,
    `AGENT_NAME="${agentName}"`,
    `AGENT_DISPLAY_NAME="${agentDisplayName}"`,
    githubAppId ? `GITHUB_APP_ID="${githubAppId}"` : "",
    githubAppInstallationId
      ? `GITHUB_APP_INSTALLATION_ID="${githubAppInstallationId}"`
      : "",
    githubAppPem
      ? `GITHUB_APP_PEM_PATH="$HOME/.proactive-engineer/github-app.pem"`
      : "",
    githubToken ? `GITHUB_TOKEN="${githubToken}"` : "",
  ]
    .filter(Boolean)
    .join(" ");

  await sandbox.runCommand("bash", [
    "-c",
    `export ${envPrefix} && export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH" && bash ~/.proactive-engineer/packer/configure-agent.sh`,
  ]);

  console.log("Verifying gateway...");
  const check = await sandbox.runCommand("bash", [
    "-c",
    'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH" && sleep 5 && cat /tmp/openclaw-pe-default.log 2>/dev/null | tail -5 || echo "Gateway starting..."',
  ]);
  console.log(await check.stdout());

  console.log("Creating snapshot...");
  const snapshot = await sandbox.snapshot({ expiration: 0 });
  console.log(`Snapshot created: ${snapshot.snapshotId}`);

  saveState({
    snapshotId: snapshot.snapshotId,
    sandboxId: sandbox.sandboxId,
    agentName,
    agentDisplayName,
    createdAt: new Date().toISOString(),
  });

  console.log("\n=== Proactive Engineer deployed to Vercel Sandbox ===");
  console.log(`Snapshot ID: ${snapshot.snapshotId}`);
  console.log(
    `\nTo keep it running, deploy the cron keepalive: vercel deploy`
  );
  console.log(
    `Or restart manually: SNAPSHOT_ID=${snapshot.snapshotId} npm run keepalive`
  );
}

main().catch((err) => {
  console.error("Deploy failed:", err);
  process.exit(1);
});
