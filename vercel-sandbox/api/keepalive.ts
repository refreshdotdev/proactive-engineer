import { Sandbox } from "@vercel/sandbox";

const SANDBOX_TIMEOUT = 45 * 60 * 1000; // 45 minutes (Hobby plan max)

export const maxDuration = 300; // 5 minutes for the cron handler itself

export async function GET(request: Request) {
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const snapshotId = process.env.SNAPSHOT_ID;
  if (!snapshotId) {
    return Response.json(
      { error: "SNAPSHOT_ID not configured" },
      { status: 500 }
    );
  }

  try {
    console.log(`Keepalive: resuming from snapshot ${snapshotId}`);

    const sandbox = await Sandbox.create({
      source: { type: "snapshot", snapshotId },
      timeout: SANDBOX_TIMEOUT,
    });

    await sandbox.runCommand("bash", [
      "-c",
      'cd ~/.proactive-engineer && git pull --quiet origin main 2>/dev/null || true',
    ]);

    await sandbox.runCommand("bash", [
      "-c",
      [
        'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.proactive-engineer/scripts/bin:$PATH"',
        "nohup openclaw --profile pe-default gateway --port 18789 > /tmp/openclaw-pe-default.log 2>&1 &",
        "disown",
      ].join(" && "),
    ]);

    await new Promise((r) => setTimeout(r, 10000));

    const check = await sandbox.runCommand("bash", [
      "-c",
      "grep -c 'slack.*connected\\|listening' /tmp/openclaw-pe-default.log 2>/dev/null || echo '0'",
    ]);
    const logOutput = await check.stdout();

    // Schedule a snapshot ~4.5 hours from now using sandbox timeout
    // The sandbox will auto-stop at timeout; the next cron run creates a fresh one from the same snapshot
    // For true state persistence, we'd need a separate process to snapshot before timeout

    return Response.json({
      status: "ok",
      sandboxId: sandbox.sandboxId,
      snapshotId,
      gatewayIndicators: logOutput.trim(),
      message: `Agent resumed from snapshot. Running for ~45 minutes until sandbox timeout.`,
    });
  } catch (err) {
    console.error("Keepalive error:", err);
    return Response.json(
      { error: String(err), snapshotId },
      { status: 500 }
    );
  }
}
