# Agent workflow

How coding agents split, verify, and stop in this repository. Product architecture
stays in [`ARCHITECTURE.md`](ARCHITECTURE.md). This file is the **task graph**.

## Stop rule

Split only work whose pieces never read each other’s results (for example iOS
chrome and Android I/O behind the same **parity** row). Sequential live-session
or watchdog work stays with one agent. One owner merges.

More agents is not a strategy. Uncoordinated parallel edits on the same file are
out of bounds.

## Diamond

When the work does split:

```text
        ┌─ worker (one file set) ─┐
plan ───┼─ worker (disjoint set) ─┼─→ verify (fresh context) ─→ merge
        └─ worker (disjoint set) ─┘
```

Verify in a **separate** context from the author. A model grading its own diff
in the same window misses most of its own mistakes. The merge owner runs
`just check` and the spec’s grep/ledger, not a self-report.

## Human gate

Put the gate where a mistake is expensive to undo, not on every step:

- Merge to `main` (PR)
- Force-push or history rewrite
- Annotated `v*` tags and GitHub Releases
- TestFlight / store publish
- Security advisory
- Frame.io keys or any real secret

`just check`, **physical** device proof, and the **parity** table are numbers
that cannot argue back.

## Loops

Every recover/fix loop has a cap: **three** rounds on the same failure, then
stop and report. Do not 1 Hz-retry a failed approach (same shape as
**enable-once** on the wire).

One writer per file. Routing lives in the plan; the model fills the jobs.

## Knowledge graph

The serving index is the **Read when** table in `AGENTS.md`. `CONTEXT.md` is the
ontology of domain terms. That pair is the GraphRAG for this repo: single-hop
“where does X live” is a pointer, not a graph query.

A committed triple store does not earn its keep here. Lookups are “open the
pointer.” `graphify-out/` is gitignored local scratch — never commit it.

Run a local graphify pass only for **multi-hop** questions (what core types a
chrome change must call, which docs name the same opcode). Entity types to
extract if you do:

| Type | Examples |
| --- | --- |
| CoreType | `FeedWatchdog`, `CameraSetMailbox`, `LiveChromeThrottle` |
| ShellSurface | live chrome, wizard, media library |
| PointerDoc | `docs/PARITY.md`, `docs/live-session.md` |
| Opcode | `0x09/0xa8`, pktType `0x02` |
| Budget | 40 Hz ACK, 5 Hz HUD |
| Assist | LUT, WAVE, ZEBRA |

Relations: `IMPLEMENTS`, `OWNS_IO`, `DOCUMENTED_IN`, `MUST_MATCH`, `MAY_DIVERGE`.
Every fact keeps a source path. Fusion (duplicate names) before you trust a path.

## When this pointer fires

Parallel workers, subagents, a recover loop, “how should agents split this,” or
a knowledge-graph / graphify request.
