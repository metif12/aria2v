# ADR-0003: what "pure V" is allowed to mean

- **Status:** accepted
- **Date:** 2026-10-03
- **Milestone:** 0

## Context

"Rewrite download management in pure V" is the sentence that started this repo.
"Pure" could mean:

1. no `C.` declarations and no `#include`;
2. no dependencies at all;
3. only code that V's stdlib already provides.

The three are different and they have different costs. This ADR picks one so the
word means something in this repo.

## Decision

**"Pure V" means: no `C.` declarations, no `#include`, and no vendored C.**

Everything in the standard library is fair game, including `os`, `net.http`,
`encoding.base64`, and `sync`. Those are part of V.

## Why

1. **The point is the build, not the holiness.** A `v` invocation that requires
   `msys64` already present, gcc already configured, and three environment
   variables set is not a pure-V build in any sense a user cares about. Removing
   the C dependency removes the toolchain dependency.
2. **V's stdlib is part of the language.** Using `net.http` is not a compromise of
   purity any more than using `os` is; it is the same kind of dependence.
3. **Rule 2 would mean writing `arr.sort()` by hand.** The rule that follows from
   actually believing it is not a rule anyone wants.

## Consequences

- A `src/**/*.c.v` file in this repo is a bug, not a feature. There is no CI check
  for it yet — the absence of one is a known gap, and the first person to write a
  `.c.v` file should add it.
- Third-party V modules are permitted but discouraged. Each one is a review of
  someone else's judgement about `unsafe`.
- `unsafe` is allowed where V requires it (`net.http`'s `voidptr` in
  `FetchConfig`) and nowhere else.

## Alternatives rejected

**"Pure" = stdlib only.** Disallows `net.http`, which is the entire premise of
ADR-0002. The two ADRs are consistent only under this reading.

**"Pure" = no `unsafe` anywhere.** V 0.5.2's `net.http` puts a `voidptr` in
`FetchConfig` and `os.args` is `[]&char`. A rule that cannot be followed is worse
than no rule.
