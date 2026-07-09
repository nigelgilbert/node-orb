# env-file validation parity with docker run semantics

**Type**: AFK

**Status:** 🔲 Not started

## Parent

[REVIEW.md](../REVIEW.md) — Addendum A3.

## What to build

`dev/run`'s env-file validation exists to guarantee the file means the same
thing to `docker run --env-file` and compose's `env_file`, but it diverges from
both in two ways (confirmed empirically in the review):

- It **rejects** indented `KEY=value` lines that `docker run --env-file`
  happily accepts — blocking `./dev/run` on a file docker considers valid.
- It **misses** inline `#` comments: `API_KEY=secret # prod` becomes `secret`
  under compose but `secret # prod` under `docker run` — exactly the
  divergence the validation claims to prevent.

Fix the validator to enforce the *intersection* the comment promises: accept
what both parsers agree on, reject anything the two would interpret
differently (inline `#` in unquoted values must be rejected with a message
explaining the ambiguity; decide-and-document the indentation stance — either
accept it because both parsers do, or reject it with an accurate reason).

## Acceptance criteria

- [ ] `API_KEY=secret # prod` in the env file makes `./dev/run` exit non-zero
      with a message naming the inline-comment ambiguity.
- [ ] The indentation case behaves per the documented decision, and the
      validator's comment accurately describes what docker run and compose
      each do.
- [ ] A plain `KEY=value` file still passes and `./dev/run` starts.

## Blocked by

None - can start immediately
