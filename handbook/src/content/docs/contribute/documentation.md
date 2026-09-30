---
title: Keeping docs current
description: Public handbook vs repo contracts. What to update in the same PR so opencapture.org/openpocketcine/docs stays accurate.
---

The public site at [opencapture.org/openpocketcine/docs](https://opencapture.org/openpocketcine/docs/)
is this Starlight handbook. It must stay current with the apps and the protocol.
That is a same-PR rule, not a follow-up.

## Two layers

| Layer | Path | Who it is for | Published? |
| --- | --- | --- | --- |
| **Public handbook** | `handbook/src/content/docs/` | Operators, new contributors, anyone on the website | Yes, at `/openpocketcine/docs/` |
| **Engineering contracts** | `docs/*.md`, `AGENTS.md`, `ANDROID.md` | Agents and maintainers (parity, live-session, budgets, hygiene) | No |

Do not paste live-session runbooks, SoftAP passwords, or packet captures into
the handbook. Common wire facts that are safe to publish live under
[Shared protocol](../../protocol/connection/). Model-specific command sets,
capability matrices, and capture findings belong under [Osmo Devices](../../devices/).
Gotchas that only agents need stay in `docs/live-session.md`.

## What to update when

| You changed | Update in the same PR |
| --- | --- |
| DUML, BLE, opcode, pktType, HEVC/AVC payload | Matching page under `handbook/src/content/docs/protocol/` |
| Device survey, model-specific command values, firmware restrictions | Matching reference under `handbook/src/content/docs/devices/`; link common definitions instead of duplicating them |
| Operator-visible chrome, assists, connection UX | [`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md) **and** the [iOS](../../apps/ios/) or [Android](../../apps/android/) app page if the public description changed |
| Build, toolchain, how to run | [Setup](../../guides/setup/) and `CONTRIBUTING.md` if GitHub workflow changed |
| Git, tags, version trains | [`docs/RELEASE.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/RELEASE.md) (not Git Flow; no `develop`) |
| Play closed testing | [`docs/android-play-ci.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/android-play-ci.md); this handbook only if the public Android install path changed |
| TestFlight / Play tester notes | [`docs/tester-notes.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/tester-notes.md) (this-build window; not the handbook) |
| Architecture seams (core vs shell) | [Architecture](../../apps/architecture/) if the public map changed; `docs/ARCHITECTURE.md` is the seam table |
| Live-path budgets (ACK Hz, HUD Hz) | `docs/PERFORMANCE.md` (not duplicated here) |
| First-run / operator copy | `docs/UX.md`; handbook only if the public FTUE description changed |
| Pairing / live-view operator FAQ (VPN, Wi-Fi join, black well) | [Troubleshooting](../../guides/troubleshooting/) and the [support page](https://opencapture.org/openpocketcine/support/) (private repo `erik-sutton95/opencapture-site`) |

A task is not done until those pages match the code. Preview with `just handbook`.
Run `just handbook-build` before publication; the build checks
rendered page routes and anchors, including translated fallback pages. Relative
links resolve from the final trailing-slash URL, not the Markdown file path.
A merge to `main` that touches `handbook/` triggers a Vercel deploy hook. The rest
of the website lives in the private repo `erik-sutton95/opencapture-site`.

## Release notes

Tester notes normally cover the current build for camera operators. For an
open-beta release with a named previous build, include all operator-visible
changes since that baseline and publish the full platform lists in the handbook.
Contract: [`docs/tester-notes.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/tester-notes.md).
Release pages archive reviewed open-beta windows; routine internal-build notes
remain in the platform files.

## One home per fact

The handbook summarizes. The contract files own the numbers and exceptions.
If a sentence would have to be edited in two places, keep it in the contract and
link here.

Agents: `AGENTS.md` **handbook** pointer. Human GitHub workflow:
[`CONTRIBUTING.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/CONTRIBUTING.md).
