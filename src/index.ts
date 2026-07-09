import { createServer } from "node:http";

// SINGLE SOURCE OF TRUTH for the app's port. Everywhere else the port is
// pinned (docker-compose.yml `environment`/`ports` and the socat forwarder
// sidecar's `command` — `TCP-LISTEN:3000`/`TCP:…:3000`, dev/run `-e PORT=…`)
// points back here in a comment — moving the app to a new port starts by
// editing this constant, then updating the call sites its comments name.
export const DEFAULT_PORT = 3000;

// `??` alone won't do here: PORT="" must fall back (Number("") is 0 → bind to
// a random port), and garbage must fail loudly instead of NaN-crashing later.
// Only plain decimal digits are accepted — Number() would otherwise quietly
// take hex ("0x50"→80), octal ("0o17"→15), and scientific ("1e3"→1000)
// notation, binding a port the operator never wrote (A4).
export function resolvePort(raw = process.env.PORT): number {
  const trimmed = raw?.trim();
  if (!trimmed) return DEFAULT_PORT;
  if (!/^\d+$/.test(trimmed)) {
    throw new Error(`invalid PORT ${JSON.stringify(raw)} — expected plain decimal digits (an integer between 1 and 65535)`);
  }
  const port = Number(trimmed);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`invalid PORT ${JSON.stringify(raw)} — expected an integer between 1 and 65535`);
  }
  return port;
}

export function greeting(): string {
  return process.env.GREETING ?? "Hello from node-orb";
}

if (import.meta.main) {
  const PORT = resolvePort(); // fail fast on misconfiguration, before binding (defaults to DEFAULT_PORT)
  const server = createServer((_req, res) => {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end(`${greeting()}\n`);
  });

  server.listen(PORT, () => {
    console.log(`⚡ ${greeting()} — listening on :${PORT} (edit src/ to reload)`);
  });

  // `docker stop` / compose send SIGTERM; finish in-flight responses and go.
  // `once`: a second SIGTERM falls through to the default handler (force-quit)
  // instead of re-running close.
  //
  // Bound the wait so an idle keep-alive socket can't hold us hostage until
  // compose's stop_grace_period (10s) SIGKILLs us — which would drop in-flight
  // responses anyway. `closeIdleConnections()` reaps sockets with no active
  // request right away; `close()` then only waits on in-flight requests, whose
  // sockets close once their response finishes. As a backstop, force-close any
  // stragglers after SHUTDOWN_TIMEOUT_MS — comfortably inside the 10s grace
  // period, so a slow client can't turn a clean SIGTERM into a SIGKILL.
  const SHUTDOWN_TIMEOUT_MS = 5000;
  process.once("SIGTERM", () => {
    server.close((err) => {
      clearTimeout(forceClose);
      if (err) {
        console.error("error during shutdown:", err);
        process.exit(1);
      }
      process.exit(0);
    });
    server.closeIdleConnections();
    const forceClose = setTimeout(() => {
      server.closeAllConnections();
    }, SHUTDOWN_TIMEOUT_MS);
    // Don't let the pending timer keep the loop alive once close() finishes.
    forceClose.unref();
  });
}

