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
  const restrictToChannel = process.env.RESTRICT_TO_CHANNEL || "";
  const advisoryOnly = process.env.ADVISORY_ONLY || "";

  console.log("Creating sandbox...");
  const sandbox = await Sandbox.create({ timeout: FIVE_HOURS });
  console.log(`Sandbox created: ${sandbox.sandboxId}`);

  console.log("Installing OpenClaw...");
  const installResult = await sandbox.runCommand("bash", [
    "-c",
    [
      "SHARP_IGNORE_GLOBAL_LIBVIPS=1 npm --loglevel error --no-fund --no-audit install -g openclaw@latest --ignore-scripts 2>&1",
      "cd $(npm root -g)/openclaw && npm rebuild --ignore-scripts 2>&1",
      "export PATH=\"$HOME/.global/npm/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH\"",
      "which openclaw && openclaw --version && echo '---INSTALL_OK---'",
    ].join(" && "),
  ]);
  const installOut = await installResult.stdout();
  console.log(installOut.slice(-200));
  if (!installOut.includes("INSTALL_OK")) {
    throw new Error("OpenClaw install failed");
  }

  console.log("Verifying OpenClaw...");
  const verify = await sandbox.runCommand("bash", [
    "-c",
    "export PATH=\"$HOME/.global/npm/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH\" && which openclaw && openclaw --version",
  ]);
  console.log(await verify.stdout());

  console.log("Cloning proactive-engineer...");
  await sandbox.runCommand("bash", [
    "-c",
    "git clone --depth 1 https://github.com/refreshdotdev/proactive-engineer.git $HOME/.proactive-engineer && ls $HOME/.proactive-engineer/skills/proactive-engineer/SKILL.md",
  ]);

  console.log("Setting up skill symlink...");
  await sandbox.runCommand("bash", [
    "-c",
    "mkdir -p $HOME/.openclaw/skills && ln -sf $HOME/.proactive-engineer/skills/proactive-engineer $HOME/.openclaw/skills/proactive-engineer && ls $HOME/.openclaw/skills/proactive-engineer/SKILL.md",
  ]);

  if (githubAppPem) {
    console.log("Writing GitHub App PEM...");
    await sandbox.runCommand("bash", [
      "-c",
      `cat > $HOME/.proactive-engineer/github-app.pem << 'PEMEOF'\n${githubAppPem}\nPEMEOF\nchmod 600 $HOME/.proactive-engineer/github-app.pem && ls -la $HOME/.proactive-engineer/github-app.pem`,
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
    restrictToChannel ? `RESTRICT_TO_CHANNEL="${restrictToChannel}"` : "",
    advisoryOnly ? `ADVISORY_ONLY="${advisoryOnly}"` : "",
  ]
    .filter(Boolean)
    .join(" ");

  await sandbox.runCommand("bash", [
    "-c",
    `export ${envPrefix} && export PATH="$HOME/.global/npm/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH" && bash ~/.proactive-engineer/packer/configure-agent.sh`,
  ]);

  console.log("Verifying gateway...");
  await new Promise((r) => setTimeout(r, 15000));
  const check = await sandbox.runCommand("bash", [
    "-c",
    'export PATH="$HOME/.global/npm/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH" && cat /tmp/openclaw-pe-*.log 2>/dev/null | tail -10 || echo "No logs yet"',
  ]);
  const checkOut = await check.stdout();
  console.log(checkOut);

  if (checkOut.includes("slack") && checkOut.includes("connected")) {
    console.log("Slack connected!");
  } else {
    console.log("Warning: Slack connection not confirmed yet. The agent may still be starting.");
  }

  console.log("Verifying files before snapshot...");
  const files = await sandbox.runCommand("bash", [
    "-c",
    'export PATH="$HOME/.global/npm/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH" && echo "openclaw: $(which openclaw)" && echo "config: $(ls ~/.openclaw-pe-default/openclaw.json 2>/dev/null || echo missing)" && echo "skill: $(ls ~/.openclaw/skills/proactive-engineer/SKILL.md 2>/dev/null || echo missing)" && echo "pem: $(ls ~/.proactive-engineer/github-app.pem 2>/dev/null || echo missing)"',
  ]);
  console.log(await files.stdout());

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

  // Auto-deploy the keepalive cron
  console.log("\nSetting up keepalive cron...");
  const { execSync } = await import("child_process");
  const cronSecret = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);

  try {
    execSync(`vercel env rm SNAPSHOT_ID production -y 2>/dev/null || true`, { stdio: "pipe" });
    execSync(`echo "${snapshot.snapshotId}" | vercel env add SNAPSHOT_ID production`, { stdio: "pipe" });
    console.log("Set SNAPSHOT_ID env var.");

    execSync(`vercel env rm CRON_SECRET production -y 2>/dev/null || true`, { stdio: "pipe" });
    execSync(`echo "${cronSecret}" | vercel env add CRON_SECRET production`, { stdio: "pipe" });
    console.log("Set CRON_SECRET env var.");

    console.log("Deploying keepalive cron to production...");
    const deployOut = execSync("vercel deploy --prod --yes 2>&1", { encoding: "utf8" });
    const prodUrl = deployOut.trim().split("\n").pop();
    console.log(`Deployed: ${prodUrl}`);
    console.log("Keepalive cron will restart the agent every 5 hours automatically.");
  } catch (e) {
    console.log("Could not auto-deploy cron. You can do it manually:");
    console.log(`  vercel env add SNAPSHOT_ID production  (value: ${snapshot.snapshotId})`);
    console.log(`  vercel env add CRON_SECRET production  (value: ${cronSecret})`);
    console.log("  vercel deploy --prod");
  }

  console.log("\n=== Proactive Engineer deployed to Vercel Sandbox ===");
  console.log(`Snapshot ID: ${snapshot.snapshotId}`);
  console.log("The agent is running and the keepalive cron will keep it alive 24/7.");
  console.log(
    `\nTo restart manually: SNAPSHOT_ID=${snapshot.snapshotId} npm run keepalive`
  );
}

main().catch((err) => {
  console.error("Deploy failed:", err);
  process.exit(1);
});
