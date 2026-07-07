import { createServer } from "node:http";

// `??` alone won't do here: PORT="" must fall back (Number("") is 0 → bind to
// a random port), and garbage must fail loudly instead of NaN-crashing later.
export function resolvePort(raw = process.env.PORT): number {
  const trimmed = raw?.trim();
  const port = trimmed ? Number(trimmed) : 3000;
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`invalid PORT ${JSON.stringify(raw)} — expected an integer between 1 and 65535`);
  }
  return port;
}

export function greeting(): string {
  return process.env.GREETING ?? "Hello from node-orb";
}

if (import.meta.main) {
  const PORT = resolvePort(); // fail fast on misconfiguration, before binding
  const server = createServer((_req, res) => {
    res.writeHead(200, { "content-type": "text/plain" });
    res.end(`${greeting()}\n`);
  });

  server.listen(PORT, () => {
    console.log(`⚡ ${greeting()} — listening on :${PORT} (edit src/ to reload)`);
  });

  // `docker stop` / compose send SIGTERM; finish in-flight responses and go.
  process.on("SIGTERM", () => {
    server.close(() => process.exit(0));
  });
}

