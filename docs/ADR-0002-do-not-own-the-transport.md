# ADR-0002: do not own the transport

- **Status:** accepted
- **Date:** 2026-10-03
- **Milestone:** 0 / 1

## Context

A download engine that calls itself one owns its transport: sockets, TLS,
redirects, chunked encoding, HTTP/2, proxies. That is a large, permanent,
security-critical surface, and it is the part with the least to do with *download
management*.

It also already exists. V's `net.http` has streaming downloads with a `Downloader`
interface, `FetchConfig.header` for `Range`, TLS, redirects, and a `Server` for
the RPC half.

## Decision

**aria2v owns the manager; `net.http` owns the wire.**

The manager is: what to download, which bytes, how many connections, resume,
progress, session, queue state. The wire is: TCP, TLS, headers, bodies.

Concretely: `internal/plan` decides *which byte ranges*; `net.http` fetches each
one. `internal/session` decides *what to remember*; `os` writes it. Nothing in this
repo reimplements HTTP, and nothing in it opens a raw socket.

## Why

1. **The interesting bugs are in the manager.** A byte-range plan that overlaps by
   one byte, a resume that trusts a stale offset, a progress bar that finishes at
   150% — those are the failures a download manager actually has, and they are the
   ones I can test without a network.
2. **A second HTTP stack is a liability, not an asset.** It would need its own
   TLS verification policy, its own proxy handling, and its own CVE pipeline, and
   none of those make the manager better.
3. **`FetchConfig.header` is enough for the multi-connection design.** `Range:
   bytes=first-last` per connection is the whole mechanism; nothing else is needed
   from the transport.

## Consequences

- `internal/plan` and `internal/session` never import `net.http`. They are pure,
  and the dependency direction is one-way.
- A bug in the transport is a bug in V's stdlib and is not fixable here. That is a
  real cost, and it is the point: it is a cost someone else carries.
- If V's `net.http` stops being good enough — no connection reuse, or a progress
  interface that cannot express what we need — this ADR is what gets revisited,
  and the plan module survives the change either way.

## Alternatives rejected

**Hand-rolled HTTP over `net.TcpConn`.** Fewer surprises, total ownership, and
about 1500 lines of protocol that would need its own test suite. Rejected on
exactly the grounds above.

**Shelling out to `curl`.** Wrong for a library, and it makes the engine a
conductor of other people's binaries, which is the thing this repo exists to stop
Fluxget doing.
