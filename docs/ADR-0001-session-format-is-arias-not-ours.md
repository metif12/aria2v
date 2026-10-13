# ADR-0001: the session file is aria2c's format, not ours

- **Status:** accepted
- **Date:** 2026-10-03
- **Milestone:** 0

## Context

A session file has to survive the app not running. It is the one artifact a
download manager cannot afford to lose, and a queue that vanishes on close is the
worst failure this kind of app has.

We could have designed a format: JSON with a schema, an immutable version field,
and a migration path. That is what a new project normally does, and it is what I
did first in my head.

## Decision

Write aria2c's `--save-session` format. Concretely:

```
https://example.com/file.bin
 dir=D:/Downloads/x
 out=renamed.bin

```

URL first, aria2's own option names below it, blank line between entries, and the
same flat shape.

## Why

1. **The cut-over has to be reversible.** A file `aria2c` wrote must be a file
   aria2v reads, and the other way round. That is what makes switching engines a
   setting instead of a migration, and a migration nobody can reverse is a
   migration nobody will approve.
2. **An empty queue is recoverable; a half-written one is not.** The atomic-write
   rule (temp file plus rename) is what makes a power cut lose at most the last
   entry. That property belongs to the write, not the schema.
3. **A better schema costs a reader we would have to maintain forever.** Two
   formats means two readers, and the second one exists only for old files.

## Consequences

- Option names in the file are aria2's (`max-connection-per-server`), not ours.
  The mapping lives in `internal/session/vocab.v` and nowhere else.
- Decoding is **lossy by design**: a line the loader cannot understand is skipped
  and counted, never fatal. See `session.v` for the rule.
- Two malformations are repaired rather than reported — a missing blank line
  between entries, and an option line with an unusable key — because reporting
  them would tell the user a download was lost when nothing was.
- A corrupt line costs **one entry, never the queue**. This is asserted by
  `test_a_corrupt_line_loses_one_entry_not_the_queue`.

## Alternatives rejected

**JSON with a version field.** Better tooling, worse reversibility, and a second
reader. Would have been the right call if the goal were the best format rather
than a replaceable engine.
