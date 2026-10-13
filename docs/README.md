# aria2v docs

Short documents about decisions, for the same reason Fluxget writes them down: a
choice you can only reconstruct from a conversation is a choice the next person
makes differently.

## Index

| Document | Question it answers |
|---|---|
| [ROADMAP.md](../ROADMAP.md) | what is built, what is next, what is **not** coming |
| [ADR-0001](ADR-0001-session-format-is-arias-not-ours.md) | why the session file uses aria2c's shape when we could design a better one |
| [ADR-0002](ADR-0002-do-not-own-the-transport.md) | why `net.http` does the wire work and this repo does not rewrite it |
| [ADR-0003](ADR-0003-pure-over-c shim.md) | what "pure V" is allowed to mean |
| [compat/fluxget.md](compat/fluxget.md) | the exact `aria2.*` subset Fluxget calls, so the cut-over is a list and not a guess |

## What is deliberately not here

- **No CHANGELOG.** `git log` is the changelog and the messages are written to be
  read. A file that repeats them drifts.
- **No design doc for each module.** The modules carry their own doc comments, and
  the rule this repo works to is that the code and its explanation live together.
- **No FAQ.** If the same question is asked twice it belongs in a doc above.
