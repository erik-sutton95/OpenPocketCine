---
title: Keeping docs current
description: Public handbook vs repo contracts. What to update in the same PR so openpocketcine.app/docs stays accurate.
---

The public site at [openpocketcine.app/docs](https://openpocketcine.app/docs/)
is this Starlight handbook. It must stay current with the apps and the protocol.
That is a same-PR rule, not a follow-up.

## Two layers

| Layer | Path | Who it is for | On Pages? |
| --- | --- | --- | --- |
| **Public handbook** | `handbook/src/content/docs/` | Operators, new contributors, anyone on the website | Yes — `/docs/` |
| **Engineering contracts** | `docs/*.md`, `AGENTS.md`, `ANDROID.md` | Agents and maintainers (parity, live-session, budgets, hygiene) | No |

Do not paste live-session runbooks, SoftAP passwords, or packet captures into
the handbook. Wire facts that are safe to publish live under [Protocol](../protocol/connection/).
Gotchas that only agents need stay in `docs/live-session.md`.

## What to update when

| You changed | Update in the same PR |
| --- | --- |
| DUML, BLE, opcode, pktType, HEVC/AVC payload | Matching page under `handbook/src/content/docs/protocol/` |
| Operator-visible chrome, assists, connection UX | [`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md) **and** the [iOS](../apps/ios/) or [Android](../apps/android/) app page if the public description changed |
| Build, toolchain, how to run | [Setup](../guides/setup/) and `CONTRIBUTING.md` if GitHub workflow changed |
| Git, tags, version trains | [`docs/RELEASE.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/RELEASE.md) (not Git Flow; no `develop`) |
| Architecture seams (core vs shell) | [Architecture](../apps/architecture/) if the public map changed; `docs/ARCHITECTURE.md` is the seam table |
| Live-path budgets (ACK Hz, HUD Hz) | `docs/PERFORMANCE.md` (not duplicated here) |
| First-run / operator copy | `docs/UX.md`; handbook only if the public FTUE description changed |

A task is not done until those pages match the code. Preview with `just handbook`.
Merge to `main` deploys Pages when `handbook/` or `site/` changed.

## One home per fact

The handbook summarizes. The contract files own the numbers and exceptions.
If a sentence would have to be edited in two places, keep it in the contract and
link here.

Agents: `AGENTS.md` **handbook** pointer. Human GitHub workflow:
[`CONTRIBUTING.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/CONTRIBUTING.md).
