import { createServer } from "node:http";

// `??` alone won't do here: PORT="" must fall back (Number("") is 0 → bind to
// a random port), and garbage must fail loudly instead of NaN-crashing later.
const rawPort = process.env.PORT?.trim();
export const PORT = rawPort ? Number(rawPort) : 3000;
if (!Number.isInteger(PORT) || PORT < 1 || PORT > 65535) {
  throw new Error(`invalid PORT ${JSON.stringify(process.env.PORT)} — expected an integer between 1 and 65535`);
}

export function greeting(): string {
  return process.env.GREETING ?? "Hello from node-orb";
}

if (import.meta.main) {
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

