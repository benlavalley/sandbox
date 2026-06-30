import { config } from "./config.ts";
import { createApp } from "./app.ts";
import { handleProxyRequest, resolveSandboxByToken, resolveSandboxId } from "./services/proxy.ts";
import { Hono } from "hono";

const { app, backends, sandboxService, ttlService } = createApp();

/** True for the low-level "can't reach the Docker daemon" errors. */
function isDockerConnError(err: unknown): boolean {
  const code = (err as { code?: string } | null)?.code;
  const msg = String((err as { message?: string } | null)?.message ?? err);
  return (
    code === "ECONNREFUSED" ||
    code === "ENOENT" ||
    code === "ECONNRESET" ||
    code === "FailedToOpenSocket" ||
    /ECONNREFUSED|FailedToOpenSocket|connect ENOENT/i.test(msg)
  );
}

function printDockerUnreachable(): void {
  console.error(`\n✖ Cannot reach the Docker daemon at ${config.dockerSocket}\n`);
  console.error("  Make sure Docker is installed, running, and up to date, then start again.");
  if (process.platform === "win32") {
    console.error(
      '  On Windows the CLI talks to Docker over TCP. In Docker Desktop turn on\n' +
        '    Settings → General → "Expose daemon on tcp://localhost:2375 without TLS"\n' +
        "  (or point DOCKER_SOCKET at your daemon, e.g. DOCKER_SOCKET=tcp://HOST:PORT).",
    );
  } else {
    console.error(
      `  Check the daemon is listening at ${config.dockerSocket} (or set DOCKER_SOCKET).`,
    );
  }
  console.error("");
}

// Backstop: if a Docker connection error escapes as an unhandled rejection,
// surface the actionable message instead of a raw stack trace.
process.on("unhandledRejection", (err) => {
  if (isDockerConnError(err)) {
    printDockerUnreachable();
  } else {
    console.error(err);
  }
  process.exit(1);
});

/** Verify the Docker backend is reachable before we claim to be listening. */
async function preflightDocker(): Promise<void> {
  if (backends.linux.type !== "docker") return;
  try {
    await backends.linux.listSandboxes();
  } catch (err) {
    if (isDockerConnError(err)) {
      printDockerUnreachable();
      process.exit(1);
    }
    throw err;
  }
}

// TTL reconciliation on startup
async function reconcileTtls() {
  const allBackends = [backends.linux, backends.macos].filter(Boolean);
  const results = await Promise.all(allBackends.map((b) => b!.listSandboxes({ state: "running" })));
  const sandboxes = results.flat();
  for (const sb of sandboxes) {
    const elapsed = (Date.now() - new Date(sb.createdAt).getTime()) / 1000;
    const remaining = sb.timeoutSec - elapsed;
    if (remaining <= 0) {
      await sandboxService.kill(sb.sandboxId);
    } else {
      ttlService.start(sb.sandboxId, remaining, () => {
        sandboxService.kill(sb.sandboxId).catch(console.error);
      });
    }
  }
  console.log(`Reconciled TTLs for ${sandboxes.length} sandbox(es)`);
}

// Fail fast with a clear message if Docker is unreachable, before we bind ports.
await preflightDocker();

reconcileTtls().catch(console.error);

// Periodic reconciliation — clean stopped VMs + expired TTLs every 30s
setInterval(async () => {
  try {
    // listSandboxes triggers stopped VM cleanup in TartBackend
    const allBackends = [backends.linux, backends.macos].filter(Boolean);
    await Promise.all(allBackends.map((b) => b!.listSandboxes()));
    await reconcileTtls();
  } catch (e) {
    console.error("Reconciliation error:", e);
  }
}, 30_000);

// Main control plane + data plane proxy (port 49982)
console.log(`Control plane listening on :${config.port}`);

Bun.serve({
  port: config.port,
  fetch: app.fetch,
});

// Envd proxy listener (port 49983)
// The E2B SDK in debug mode connects directly to localhost:49983.
// This listener proxies those requests to the correct container's mapped port.
if (config.port !== config.envdProxyPort) {
  const envdProxy = new Hono();
  envdProxy.all("*", async (c) => {
    // Resolve sandbox from E2b-Sandbox-Id header, access token, or fallback
    let sandboxId = c.req.header("E2b-Sandbox-Id") ?? undefined;
    if (!sandboxId) {
      const accessToken = c.req.header("X-Access-Token");
      if (accessToken) {
        sandboxId = resolveSandboxByToken(accessToken);
      }
    }

    // Resolve to a real sandbox (handles "debug_sandbox_id" and missing IDs)
    const resolved = sandboxId
      ? await resolveSandboxId(sandboxId, backends)
      : null;

    // If still unresolved, try to find the single running sandbox
    const finalId = resolved ?? (await resolveSandboxId("", backends));

    if (!finalId) {
      return c.json(
        { code: 502, message: "No running sandbox found" },
        502,
      );
    }

    return handleProxyRequest(c, backends, finalId);
  });

  Bun.serve({
    port: config.envdProxyPort,
    fetch: envdProxy.fetch,
  });

  console.log(`Envd proxy listening on :${config.envdProxyPort}`);
}
