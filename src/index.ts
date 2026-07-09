import { createServer } from "node:http";

// SINGLE SOURCE OF TRUTH for the app's port. Everywhere else the port is
// pinned (docker-compose.yml `environment`/`ports`, dev/run `-e PORT=…`) points
// back here in a comment — moving the app to a new port starts by editing this
// constant, then updating the two call sites its comments name.
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
  process.once("SIGTERM", () => {
    server.close((err) => {
      if (err) {
        console.error("error during shutdown:", err);
        process.exit(1);
      }
      process.exit(0);
    });
  });
}

