import { test } from "node:test";
import assert from "node:assert/strict";
import { greeting, resolvePort } from "./index.ts";

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
