# The aria2.* surface Fluxget calls

The list this repo has to implement for the cut-over to be a settings change.

It was extracted from Fluxget at commit `791ebc6` — from `rpc/rpc.v`, not from
aria2's documentation, because what matters is what the app *does*, not what the
engine *offers*.

## How Fluxget talks to aria2 today

Loopback HTTP JSON-RPC, `POST /jsonrpc`, `X-Rpc-Secret` or `?token=<secret>`, one
`system.multicall` per tick batching six calls. See `rpc/rpc.v` in Fluxget for the
exact shapes; the ones worth knowing before implementing:

- the token is a **leading** `token:<secret>` argument on every RPC call, and it is
  *not* repeated inside the multicall's inner calls;
- every numeric field arrives as a **string** (`"completedLength":"1048576"`);
- `aria2.getUris` returns **one row per source, expanded** — two URLs submitted
  come back as five rows;
- `aria2.tellStatus` answers with `errorCode` and `errorMessage` for a failed
  download, and **never** with `error`.

Those four were each established against `aria2c 1.37.0` with `curl`, not read from
docs, and they are the ones a reimplementation gets wrong.

## The subset, by group

### Downloads
| Method | Fluxget uses it for |
|---|---|
| `aria2.addUri` | adding a URL, a magnet, or mirrors as one call |
| `aria2.addTorrent` | adding `.torrent` bytes |
| `aria2.tellStatus` | every row in the queue |
| `aria2.tellActive` / `tellWaiting` / `tellStopped` | the snapshot, one call each |
| `aria2.pause` / `aria2.unpause` | row actions |
| `aria2.pauseAll` / `aria2.unpauseAll` | queue actions |
| `aria2.remove` | taking a download off the queue |
| `aria2.removeDownloadResult` | discarding its record |
| `aria2.getFiles` | a torrent's file list |
| `aria2.getServers` | tracker list |
| `aria2.getUris` | the mirror set, and which one is in use |
| `aria2.getOption` / `aria2.changeOption` | per-download options |
| `aria2.getPeers` | the peers dialog |

### Session and options
| Method | Fluxget uses it for |
|---|---|
| `aria2.getGlobalStat` | the speed and counts |
| `aria2.getVersion` | readiness and the version card |
| `aria2.getGlobalOption` | reading back what is in force |
| `aria2.changeGlobalOption` | pushing the settings document |
| `aria2.saveSession` | before shutdown, so a crash costs one interval |
| `aria2.shutdown` | graceful stop |

### System
| Method | Fluxget uses it for |
|---|---|
| `system.multicall` | the tick's six calls in one round trip |
| `system.listMethods` | not called, but the framework's own examples rely on it |

## What this list is not

It is **not** a promise that aria2v will implement all of it. The roadmap decides
that; this document decides what "done" means when it gets there. Anything not on
this list is not needed by Fluxget, however much aria2 has it.

## Keeping it true

Fluxget's `scripts/check-isolation.ps1` and `platform/contract.v` are the source
of truth for what Fluxget imports; this file is a translation of that into
"methods to implement". If the two disagree, Fluxget is right.
