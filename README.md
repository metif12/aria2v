# aria2v

A download engine in pure V. Not a fork of aria2 — the part of it Fluxget needs,
written from scratch, with the same JSON-RPC surface so the swap is reversible.

## Why this exists

Fluxget is a download manager built on top of `aria2c` as a child process. That
was the right call and it is documented in
[ADR-0003](../fluxget/docs/ADR/0003-compete-without-owning-the-transfer.md): owning
the transfer means owning BitTorrent's attack surface, and a download manager with
a webview in it should not.

This repo exists for the three reasons a fork of C++ is not a good answer, and it
is scoped to those:

1. **Fluxget runs on Windows only today, and aria2c ships as a GPL binary from a
   script.** A pure-V engine is built by the same `v` that builds the app.
2. **The protocol a desktop download manager actually needs is HTTP.** BitTorrent
   is the 30% that costs 80% of the code, and it is not needed for a first release.
3. **A compile error is a build failure; a segfault in `aria2c 1.37.0` at 3am is a
   bug report with no stack.**

It is NOT a drop-in replacement for aria2c today. What it does is below.

## What it does

| | |
|---|---|
| **Multi-connection downloads over HTTP(S)** | One file, N ranges, `Range: bytes=first-last`. The split is even with the remainder on segment zero, which is what aria2 does and what makes the progress bar finish when it looks finished. |
| **Resume** | Reads what is on disk and plans only the remainder. An offset that overshoots the file yields an empty plan rather than a request for a byte that does not exist. |
| **Minimum segment size** | A file too small to split is fetched with one connection, because eight 128 KiB pieces each cost a round trip and finish no sooner. |
| **Session save/restore in aria2's own format** | `--save-session` written flat, atomic by rename, and a reader that loses **one** line on corruption rather than the whole queue. |
| **Mirror sets** | De-duplicated, ordered, and labelled by kind — a `.torrent` path is bytes, a magnet is its own protocol, a URL is HTTP. |
| **Per-download options** | Where aria2's own option names apply. |

What it reads is what `aria2c 1.37.0` was measured to write on this machine: a
multi-mirror `addUri` comes back from `aria2.getUris` as **five rows for two
URLs**, because aria2 expands the set internally. A reader that mapped rows to
mirrors one-for-one would report a per-mirror count that is a fiction.

## What it does not do

Honest, because a list like this is the only thing that makes the list useful.

- **BitTorrent.** The whole protocol: swarm, peers, trackers, DHT, PEX, piece
  selection, the rarest-first policy. This is the 80%.
- **Metalink.**
- **FTP / SFTP** (aria2's `net.ftp` has something to build on).
- **Checksums** — algorithm dispatch, and the resume question of which checksum
  wins when two definitions disagree.
- **Cookie/robots handling, mirror liveness probing.**
- **The daemon part** — this is the engine, and Fluxget already owns the
  supervision (restart, backoff, readiness) in `aria2ctl/`.

## Layout

```
v.mod
main.v                    the CLI
internal/
  plan/    plan.v         how one download is split into byte ranges
  link/    link.v         what an address means, and what to call the file
  session/ session.v      the queue on disk, in aria2's format
```

`plan`, `link` and `session` are pure: no sockets, no files except the session's
own temp files, no time. They are tested against strings, which is why the
interesting bugs are found without a network.

The transfer itself uses V's `net.http`, which already does TLS, redirects,
chunked encoding, and streaming with a `Downloader` interface. Hand-rolling that
would be a second implementation of a protocol this project does not want to own.

## The RPC surface, and the cut-over

The plan is to expose the subset of `aria2.tellStatus` / `addUri` / `pause` /
`unpause` / `remove` / `getGlobalOption` / `system.multicall` that Fluxget already
calls, on the same loopback HTTP JSON-RPC shape. Then the swap is a change of host
and port, and reverting is the same change backwards.

That is not written yet. This commit is the foundation and the tests for it.

## Building and testing

```powershell
v test ./...          # all modules
v run . -- plan https://example.com/f.bin 1048576
```

V 0.5.2 is required. `v fmt` is law.

## Network use

Tests are network-free and stay that way. The one exception is an opt-in smoke
test, behind `ARIA2V_SMOKE_URL`, capped at 1 MiB, the same ceiling Fluxget uses.
