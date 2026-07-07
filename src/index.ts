import { createServer } from "node:http";

export const PORT = Number(process.env.PORT ?? 3000);

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
}

