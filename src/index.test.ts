import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { connect, createServer } from "node:net";
import { fileURLToPath } from "node:url";
import { greeting, resolvePort } from "./index.ts";

const ENTRY = fileURLToPath(new URL("./index.ts", import.meta.url));

// Ask the OS for a free port, then release it so the child can bind it. The
// strict parser rejects PORT=0, so the child can't self-allocate — we allocate
// out-of-band and hand it a concrete number. Small TOCTOU window between close
// and the child's bind, but far tighter than a blind random high-port pick
// (which collides with whatever CI already has bound in that range).
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const addr = probe.address();
      if (addr === null || typeof addr === "string") {
        probe.close(() => reject(new Error("could not determine free port")));
        return;
      }
      const { port } = addr;
      probe.close(() => resolve(port));
    });
  });
}

// Spawn the real server on a free port and wait until it's listening.
async function startServer(): Promise<{
  child: ReturnType<typeof spawn>;
  port: number;
}> {
  const port = await freePort();
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [ENTRY], {
      env: { ...process.env, PORT: String(port), GREETING: "Hello from test" },
      stdio: ["ignore", "pipe", "inherit"],
    });
    let buf = "";
    child.stdout!.on("data", (d) => {
      buf += d.toString();
      if (/listening on :\d+/.test(buf)) resolve({ child, port });
    });
    child.once("error", reject);
    child.once("exit", (code) =>
      reject(new Error(`server exited early (code ${code}) before listening`)),
    );
  });
}

function waitForExit(
  child: ReturnType<typeof spawn>,
): Promise<{ code: number | null; signal: NodeJS.Signals | null }> {
  return new Promise((resolve) =>
    child.once("exit", (code, signal) => resolve({ code, signal })),
  );
}

test("SIGTERM exits 0 quickly even with an idle keep-alive connection held open", async () => {
  const { child, port } = await startServer();

  // Open a raw socket, send one keep-alive request, read the response, then sit
  // idle (never close). Without closeIdleConnections() this would pin the server
  // open until SIGKILL.
  const sock = connect(port, "127.0.0.1");
  await new Promise<void>((res) => sock.once("connect", () => res()));
  await new Promise<void>((res) => {
    sock.once("data", () => res());
    sock.write(
      `GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n`,
    );
  });

  const start = Date.now();
  const exited = waitForExit(child);
  child.kill("SIGTERM");
  const { code, signal } = await exited;
  const elapsed = Date.now() - start;

  sock.destroy();
  assert.equal(signal, null, "must exit cleanly, not via SIGKILL");
  assert.equal(code, 0, "must exit 0");
  assert.ok(elapsed < 9000, `expected fast exit, took ${elapsed}ms`);
});

test("an in-flight request at SIGTERM time still receives its response", async () => {
  const { child, port } = await startServer();

  const sock = connect(port, "127.0.0.1");
  await new Promise<void>((res) => sock.once("connect", () => res()));

  let response = "";
  sock.setEncoding("utf8");
  sock.on("data", (d) => (response += d));

  // Fire the request, then immediately SIGTERM — the response must still arrive.
  sock.write(`GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n`);
  child.kill("SIGTERM");

  // Gate on the body actually landing (or the socket ending) rather than racing
  // the last 'data' event against child exit — otherwise the assertions below
  // can fire before the final chunk is appended to `response`.
  await new Promise<void>((res) => {
    const done = () => {
      if (/HTTP\/1\.1 200/.test(response) && /Hello from test/.test(response)) res();
    };
    sock.on("data", done);
    sock.once("end", () => res());
    done(); // in case the full response already arrived synchronously
  });

  const { code } = await waitForExit(child);
  sock.destroy();

  assert.equal(code, 0);
  assert.match(response, /HTTP\/1\.1 200/);
  assert.match(response, /Hello from test/);
});

test("greeting falls back to the default when GREETING is unset", () => {
  delete process.env.GREETING;
  assert.match(greeting(), /Hello from/);
});

test("greeting honors the GREETING env var", () => {
  process.env.GREETING = "howdy";
  assert.equal(greeting(), "howdy");
});

test("resolvePort defaults to 3000 when PORT is unset", () => {
  // Clear the host/CI PORT first (mirrors the greeting test's GREETING delete);
  // resolvePort(undefined) reads process.env.PORT via its default param, so an
  // exported PORT would otherwise flip this result. See REVIEW.md Finding 7.
  delete process.env.PORT;
  assert.equal(resolvePort(undefined), 3000);
});

test("resolvePort treats empty and whitespace-only PORT as unset", () => {
  assert.equal(resolvePort(""), 3000);
  assert.equal(resolvePort("   "), 3000);
});

test("resolvePort parses a valid PORT, ignoring surrounding whitespace", () => {
  assert.equal(resolvePort("8080"), 8080);
  assert.equal(resolvePort(" 8080 "), 8080);
});

test("resolvePort rejects garbage and out-of-range values", () => {
  for (const bad of ["abc", "80.5", "-1", "0", "65536", "8080x"]) {
    assert.throws(() => resolvePort(bad), /invalid PORT/, `expected ${JSON.stringify(bad)} to be rejected`);
  }
});

test("resolvePort rejects non-decimal notation instead of silently binding", () => {
  // Number() would accept these (0x50→80, 1e3→1000, 0o17→15) and bind a port
  // the operator never wrote. Only plain decimal digits are valid. REVIEW A4.
  for (const bad of ["0x50", "1e3", "0o17", "0b101", "+80", "0X1F"]) {
    assert.throws(() => resolvePort(bad), /invalid PORT/, `expected ${JSON.stringify(bad)} to be rejected`);
  }
});
