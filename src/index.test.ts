import { test } from "node:test";
import assert from "node:assert/strict";
import { greeting } from "./index.ts";

test("greeting falls back to the default when GREETING is unset", () => {
  delete process.env.GREETING;
  assert.match(greeting(), /Hello from/);
});

test("greeting honors the GREETING env var", () => {
  process.env.GREETING = "howdy";
  assert.equal(greeting(), "howdy");
});
