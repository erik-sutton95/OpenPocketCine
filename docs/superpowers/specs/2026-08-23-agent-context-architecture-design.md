# Agent context architecture

**Date:** 2026-08-23
**Status:** implemented on `docs/agent-context-architecture`
**Slice:** 1 of 6 (index + split the two bloated loads)

OpenPocketCine’s always-loaded agent context is a thin index. Durable seams, operator
parity, Android build, and live-session runbooks are disclosed behind trigger-worded
pointers so agents get the invariant right the first time without eating the window.

This is a documentation and agent-rules change. The Swift core + SwiftUI iOS + Compose
Android architecture does not change.

## Goal

Agents (any client that reads `AGENTS.md`) take the same *process* every run:

1. Name the surface (core, iOS shell, Android shell, docs).
2. Load every pointer whose trigger matches.
3. If the change is operator-visible, hold **parity** or record the exception.

Humans keep a readable map. One home per fact. No second copy of the rules in a
client stub.

## Non-goals (later slices)

- UX / FTUE design contract
- `SECURITY.md` rewrite
- Knowledge graph / graphify corpus
- Task-graph orchestration docs (diamond, bounded loops) as a standalone system
- Deleting `STATUS.md` / `OVERNIGHT.md` / `.planning/` (already gitignored)
- `docs/agent/` tree, `llms.txt`, extra Cursor/Gemini/Windsurf instruction files
- Code, Gradle, or `just` recipe changes except to fix a link this slice breaks

## Constraints

- `AGENTS.md` is canonical for every agent. Client stubs are pointers only.
- Always-loaded budget: about 90–110 lines. Today `CLAUDE.md` also always-imports
  `docs/ARCHITECTURE.md`; that import goes away (net context drop).
- Positive phrasing first. A prohibition earns its place only as a hard gate
  (forbidden paths, no direct commits to `main`).
- Environment is source of truth for commands: `just` lists recipes. Do not
  restate the meta-check tool list in `AGENTS.md`.
- Leading words are the same tokens in `AGENTS.md`, `CONTEXT.md`, and pointers.
- `STATUS.md`, `OVERNIGHT.md`, and `.planning/` are not current. Already gitignored.

## Information hierarchy

```text
always-loaded:     AGENTS.md
client stubs:      CLAUDE.md, CODEX.md, GROK.md  (pointer to AGENTS.md; no @import)
disclosed:         CONTEXT.md, docs/ARCHITECTURE.md, docs/PARITY.md,
                   ANDROID.md, docs/live-session.md, docs/feed-watchdog.md,
                   handbook/, docs/commit-hygiene.md, CONTRIBUTING.md
sediment:          STATUS.md, OVERNIGHT.md, .planning/,
                   docs/connection-reliability-plan.md (dated PR plan)
```

### Always-loaded: `AGENTS.md`

Order of sections (do not add others):

1. Identity (2–3 lines, current opening)
2. Stack & paths (lookup; `just` is the command index; drop the meta-check tool list)
3. Hard rules
4. Before you edit (steps)
5. Read when (pointer table)
6. Verification
7. Completion
8. Sediment (one short paragraph)

### Hard rules (every branch)

Keep the Swift core **portable**: Foundation-only protocol and business logic.

Live view is **enable-once**: `0x09/0xa8` starts the stream and is the only PLI.
After picture, further enables follow the **watchdog** only.

**Hygiene:** secrets, camera Wi-Fi passwords, PII, unofficial LUT dumps, and
`captures/`, `Osmo LUTS/`, `vendor/`, `ref/`, `.local/` stay out of git. Official
Rec.709 cubes under `ios/OpenPocketCine/Resources/` and
`Apps/Android/app/src/main/assets/luts/` are tracked.

Work on a branch and open a PR. Conventional Commits
(`feat:`, `fix:`, `docs:`, `chore:`, `ci:`, `build:`, `test:`).

`AGENTS.md` is canonical for every agent. Client stubs (`CLAUDE.md`, `CODEX.md`,
`GROK.md`) are pointers only — do not copy these rules into a second instruction
file. Do not add Cursor, Copilot, Gemini, or Windsurf instruction dumps.

Replace today’s “Claude Code and Codex only” paragraph with the paragraph above.

### Before you edit (in-file steps)

1. Name the surface: core, iOS **shell**, Android **shell**, or docs.
2. Load every pointer whose trigger matches.
3. If the change is operator-visible, read **parity** and touch both shells or
   record the exception in `docs/PARITY.md`.

Done when each matching pointer has been read (not when the table has been
noticed).

### Pointer table

Front-load the leading word. One trigger line per file. Wording is the
invocation; do not add a second sentence of identity the target already carries.

| Pointer (write this line) | Target |
| --- | --- |
| **naming** — fuzzy term, new name, operator-visible copy | `CONTEXT.md` |
| **seams** — new module, core vs shell, spine order | `docs/ARCHITECTURE.md` |
| **parity** — chrome, assist, connection UX, one-platform feature | `docs/PARITY.md` |
| **JNI** — Gradle, Swift-for-Android, `.so`, facade, OpenZCine pattern | `ANDROID.md` |
| **live-session** — freeze, black feed, reconnect, UDP bind, ACK, decoder | `docs/live-session.md` |
| **watchdog** — stall, GOP-reset grace, recover `0x09/0xa8` | `docs/feed-watchdog.md` |
| **protocol** — DUML, BLE, opcode, pktType, HEVC/AVC payload | `handbook/src/content/docs/` |
| **hygiene** — commit/PR that might touch secrets, LUTs, captures, identity | `docs/commit-hygiene.md` |
| **contributing** — issues vs discussions, labels, human setup | `CONTRIBUTING.md` |

Do not pointer `docs/connection-reliability-plan.md` from `AGENTS.md`. Load it
only when executing that dated plan.

### Verification and completion

Keep `just check`, `just native-check`, `just android-check`.

**physical:** operator-visible work is proven on a real iPhone or Android device
for the platform changed. Simulator has no BLE or camera Wi-Fi. Compile-only is
not done.

A task is not done until `just check` is green for the paths touched, docs that
describe the behavior are updated, **parity** is held or an exception is recorded
in `docs/PARITY.md`, no forbidden paths are staged, and operator-visible work is
**physical** for the platform changed.

### Sediment

`STATUS.md`, `OVERNIGHT.md`, and `.planning/` are local or dated notes. They are
not current architecture. `docs/connection-reliability-plan.md` is a dated PR
plan, not a contract.

## Client stubs

`CLAUDE.md`, `CODEX.md`, and `GROK.md` are 8–12 lines. They do **not**
`@import` `AGENTS.md` or Architecture. Claude Code, Codex, and Grok already
load root `AGENTS.md`; an extra import would double-pay. Stubs exist so a
client that only reads its own filename still finds the pointer.

Template (same body, title differs):

```markdown
# OpenPocketCine <client> guide

Canonical project guidance is [`AGENTS.md`](AGENTS.md). Do not copy it here.

Operator-visible UI: prove on a **physical** device. See `AGENTS.md` → Verification.
```

Claude’s current `@import AGENTS.md` and `@import docs/ARCHITECTURE.md` are
removed.

Do not add stubs for Cursor, Copilot, Gemini, or Windsurf. Those agents still
read `AGENTS.md` if present; we do not ship a second copy of the rules under
their filenames.

## `CONTEXT.md` (repo root)

Glossary only. No opcodes-as-tutorials, no file-tree, no “how to implement.”
Format: term, one or two sentences, `_Avoid_` aliases. Include exactly these
terms:

| Term | Definition | Avoid |
| --- | --- | --- |
| **Core** | The portable Swift protocol and business-logic package (`OpenPocketViewCore`). | SDK, engine, shared module |
| **Shell** | The platform app that owns I/O and UI: SwiftUI on iOS, Compose on Android. | client, frontend, app layer |
| **Facade** | The Android JNI session boundary (`OpenPocketCineAndroidFacade`). | bridge, wrapper |
| **Spine** | Required connection order: BLE → SoftAP → UDP datalink → live view. | pipeline, stack |
| **SoftAP** | The camera’s Wi-Fi access point at `192.168.2.1`. | hotspot (except when naming the iOS API) |
| **Datalink** | UDP port 9004 DUML transport between phone and camera. | media port, stream |
| **Enable-once** | `0x09/0xa8` starts live view and is the only PLI; it is not a 1 Hz keyframe loop. | IDR loop, live-start (alone) |
| **Watchdog** | Portable stall-and-recover policy (`FeedWatchdog`). | keepalive, heartbeat |
| **Chrome** | Operator HUD around the picture (bars, chips, DISP), not the picture. | UI, overlay |
| **Parity** | Operator-visible match to the iOS baseline unless `docs/PARITY.md` lists an exception. | pixel-identical, 1:1 clone |
| **Assist** | A monitor tool on the picture (LUT, peaking, zebra, scopes, grids). | filter, effect |
| **Physical** | Proof on a real phone. Simulator cannot exercise BLE or camera Wi-Fi. | on-device (prefer **physical**) |
| **Hygiene** | Secrets, captures, unofficial LUTs, and PII stay out of git. | cleanliness |
| **Portable** | Foundation-only core: no SwiftUI, UIKit, Android, Compose, or filesystem I/O. | cross-platform, shared |

Do not add general programming terms (timeout, adapter, test).

## Split ledger

Move facts; do not leave the essay in two homes. After the split, a search for
the Samsung `:9004` story finds it in `docs/live-session.md` only.

### `docs/ARCHITECTURE.md` (durable seams)

Keep:

- Opening sentence (shared Swift core, native shells)
- Layer table, trimmed (see cells below)
- Lucide HUD glyph paragraph + `xcodegen` line
- Connection spine as **six short steps** (one to two sentences each)
- Policy-in-Swift table, plus a new row for `CameraSetMailbox`
- “Shells own sockets, BLE, SoftAP, permissions, lifecycle, rendering, storage, UI”
- Pointers to **live-session**, **watchdog**, **parity**, **JNI**, handbook

Layer cells after trim:

| Layer | Purpose cell |
| --- | --- |
| Shared core | DUML, commands, status, LUTs, layout policy. **Portable** Foundation. |
| iOS app | SwiftUI **shell**, CoreBluetooth, NEHotspotConfiguration, sockets, VideoToolbox/Metal. Teardown: **live-session**. |
| Android app | Compose **shell**. Live picture and HUD I/O: `ANDROID.md`. Operator-visible behavior: **parity**. Teardown: **live-session**. |
| Android facade | Swift session and JNI boundary |
| Tests | Swift Testing suite for the portable core |

Spine after trim (invariants stay; stories leave):

1. BLE scan and pair (GATT FFF0).
2. Read camera Wi-Fi credentials.
3. Join SoftAP `192.168.2.1`. On-path only after DHCP `192.168.2.2…254`
   (`CameraSoftAP.isAssociatedIPv4`).
4. UDP DUML to `192.168.2.1:9004` on an **ephemeral local port**. Camera 9004 is
   the remote only. Bind and ACK details: **live-session**.
5. Enable live view **enable-once** after path + display are ready. Arm pktType
   `0x02` ingest on that write. Recover policy: **watchdog**.
6. Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p. Decoder setup and
   NAL latch: **live-session**.

Add to the policy table:

| Policy | Core type | Shell I/O |
| --- | --- | --- |
| Camera SET mailbox, retransmit, settle | `CameraSetMailbox` | iOS `fireCamera`; Android JNI |

Remove from Architecture (move to **live-session**):

- iOS disconnect-teardown sentence in the layer table
- Android Vulkan / Kyant / scope / chrome-scale / fillCrop essay in the layer table
- Samsung local `:9004` bind story
- Mimo ephemeral-port citation as a narrative (the rule “ephemeral local port” stays)
- TCP 7001 poke across UDP rebuilds
- `0x02/0x68` payload `08`, 200 ms ACK wait, 40 Hz `0x04` ACK pump
- Leftover GOP P-frames / in-app Disconnect driver+decoder drop / cancelled `open()`
- TRAIL P-frames and HEVC `IDR_N_LP` (`0x28`) vs AVC latch
- “iOS is the operator-proven datalink” 5-tuple paragraph and
  `bindProcessToNetwork(null)` while `isProcessBound`
- Pointer to `docs/connection-reliability-plan.md` as if it were architecture

### `docs/live-session.md` (new; current datalink/decoder runbook)

Title: Live session. Opening: current I/O facts for the live UDP session and
platform decoders. Not a diary. Not the stall state machine (**watchdog** owns
that).

Must contain, as colocated headings:

1. **5-tuple** — iOS binds DHCP IPv4 + ephemeral local port
   (`NWParameters.requiredLocalEndpoint` port 0). Android
   `bindProcessToNetwork` then UDP `0.0.0.0:0` after `Network.bindSocket`.
   Camera `192.168.2.1:9004` is the remote only. Local `:9004` on Samsung
   accepted handshake + `0x01` and dropped pktType `0x02`.
2. **ACK pump** — pktType `0x04` at 40 Hz, cursor = latest video transport seq.
   Keep TCP 7001 poke across UDP rebuilds.
3. **Enable write** — arm pktType `0x02` ingest on the enable write; do not wait
   for a DUML ACK (VPS is 25–167 ms). Pocket may send `0x02/0x68` payload `08`
   immediately before `0x09/0xa8`. **Enable-once** (hard rule); further enables
   follow **watchdog**.
4. **Disconnect teardown** — bump `udpGeneration` / closed flag, drop callbacks
   and ACK pump, invalidate VT + flush layer on iOS, join MediaCodec output
   thread + unbind Surface on Android. Cancelled `open()` must not publish LIVE
   (`CameraSoftAP.shouldCommitLiveHandshake`).
5. **Decoder latch** — configure from VPS/SPS/PPS (`0x40/0x42/0x44`) or Nano AVC
   SPS/PPS (`0x67/0x68`). Leftover TRAIL P-frames and HEVC `IDR_N_LP` (`0x28`)
   must not latch AVC.
6. **Foreground / SoftAP flap** — iOS `noteSceneBecameActive` →
   `recoverAfterForeground`. Mid-session SoftAP `onLost` is a Network-object
   replace until grace expires; do not `bindProcessToNetwork(null)` while
   `isProcessBound` is still true.
7. **Pointers** — stall/recover → `docs/feed-watchdog.md`; wire format →
   handbook live-view; operator-visible match → `docs/PARITY.md`.

Do not copy the FeedWatchdog grace table into this file.

### `docs/PARITY.md` (new; operator-visible contract)

Opening: iOS is the operator-proven baseline. Android matches operator-visible
behavior unless a row lists an exception. GPU backends, Bluetooth stacks, and
OS APIs may diverge. Shipping a one-platform operator-visible change without a
row here is incomplete.

Rule for agents: before changing an operator-visible surface, read this file.
Ship both shells or write the exception in the table in the same PR.

| Surface | Must match | May diverge | Verify |
| --- | --- | --- | --- |
| Connection FTUE and spine | BLE → SoftAP → UDP; **enable-once**; ephemeral local port; arm `0x02` on enable write; disconnect drops driver + decoder; session recovery holds last frame | iOS `NEHotspotConfiguration` vs Android `WifiNetworkSpecifier` + `bindProcessToNetwork`; Network.framework vs Android sockets | **physical** both |
| Live chrome | DISP 1/2 maps, layout metrics (`LiveDesign` / `fillCrop` / screen-flip pillarbox), picker chrome, record as bottom sheet, zoom chip, gimbal 1–5 gain, rec lamp `pressShutter` | iOS Liquid Glass vs Kyant (API 33+ and ≥4 GB; else solid frost); SF Symbols / Material only where Lucide catalog has not replaced them | **physical** both |
| Assists | Toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, AUDIO, GUIDES, GRID, CROSS, MIRROR); long-press options; WAVE hold-without-drag opens options; scope plate metrics (`ScopeMiniChrome`) | Metal vs Vulkan vs GLES; Vision vs `android.media.FaceDetector`; PixelCopy / Kyant sampling | **physical** both |
| Camera SETs | `CameraSetMailbox` fire-and-forget + 300 ms retransmit + 2 s settle; missed ACK does not revert HUD; ISO D-Log ↔ D-Log2 hop; audio blobs and tap-focus stay round-trips | JNI vs Swift `fireCamera` | **physical** both |
| Zoom | Chip 1×→3×→6×→12×; `CamFov` hybrid readout; pinch at 20 Hz without ACK wait; D-Log2 hops to D-Log off 1× | Hit-testing over SurfaceView vs SwiftUI | **physical** both |
| Tracking | Long-press+drag search box `0x02/0xA6`; tap face bracket → ActiveTrack; green cancel X and focus-reset | Face detector implementation | **physical** both |
| Operator Setup | Seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System); DJI Black; Sora + IBM Plex; NOTICE legal | Frame.io row is “Not configured” until iOS keys exist | **physical** both |
| Media | Camera catalog, SoftAP HTTP cache, 720p LRF/XRF proxy playback, independent playback assist rail, live HEVC held while library covers the monitor | Frame.io C2C and LUT bake on export: iOS only. Android share/save uses the original (`MediaHTTP.deliveryPath`). Playback chrome is an 82% DJI-black plate (no Kyant). | **physical** both |
| Explicit skip | — | VideoToolbox, MetalFX super-res, iOS 26 Liquid Glass API, Frame.io OAuth, LEVEL / De-SQ / MAG | n/a |

Pixel-level numbers that are the contract (drum faces 27/20 pt, 0.72 plates,
histogram gutters 17.5 dp, FORMAT/COLOR 340 dp host) live in `docs/PARITY.md`
as a short **Chrome metrics** subsection, moved from `ANDROID.md` and not
duplicated back.

### `ANDROID.md` (build / JNI / I/O)

Keep:

- Title, “not on Play”, iOS is the daily driver
- How the Android build is structured (five steps)
- Pocket mapping table
- Do not copy from OpenZCine Android
- First Android milestone (short)
- OpenZCine Android patterns adopted (Keystore, `WIFI_MODE_FULL_LOW_LATENCY`,
  haptics, SDK 36 gate, `CubeLUT` packer, GLES fallback, media cache,
  sticky battery)

Replace the “Operator parity (iOS baseline)” essay with:

- One paragraph: operator-visible behavior lives in `docs/PARITY.md`. This file
  is the Android build and I/O notes that implement those rows.
- I/O notes grouped by surface (Connection, Live picture, HUD glass, Assists
  GPU, Media decode) — **how Android does it**, not the contract. Each note is
  one or two sentences: `bindProcessToNetwork`, MediaCodec `KEY_LOW_LATENCY` /
  wall-clock PTS, Vulkan `libopc_vulkan.so` path, Kyant hardware gate,
  PixelCopy ~20 Hz, GLES `FeedEffectsGlProgram` fallback, ExoPlayer OES
  playback, Wi-Fi creds in private prefs not saved-camera JSON, `holdsMonitor`
  first-picture recover.

Do not restate enable-once, ephemeral port, or mailbox semantics here. Point at
**live-session** / **parity**. Target: `ANDROID.md` stays a build/I/O guide a
person can read in one sitting, not a paste of the old parity essay.

## Other edits in this slice

- `CONTRIBUTING.md`: add one sentence under Code standards — agent instructions
  live in `AGENTS.md`; do not copy them here. Leave the rest of CONTRIBUTING
  alone. Deduping its standards against `AGENTS.md` is a later hygiene slice.
- `docs/ARCHITECTURE.md` “See” links: `feed-watchdog.md`, `live-session.md`,
  `PARITY.md`, handbook. Drop the architecture-level pointer to
  `connection-reliability-plan.md`.
- No README rewrite. No handbook rewrite. No `justfile` change unless a
  markdown link check requires it.

## Implementation order (for the plan, not this spec)

1. Add `CONTEXT.md`.
2. Add `docs/live-session.md` from the Architecture ledger (copy then delete).
3. Slim `docs/ARCHITECTURE.md`.
4. Add `docs/PARITY.md` from the Android ledger (copy then delete).
5. Slim `ANDROID.md`.
6. Rewrite `AGENTS.md`.
7. Rewrite `CLAUDE.md`; add `CODEX.md` and `GROK.md`.
8. One-line `CONTRIBUTING.md`.
9. `just check`.

One writer per file in a given step. Do not leave a fact in the old home after
the new home exists.

## Verification of this slice

- `just check` (hygiene, typos, markdown, links). Docs-only: not `native-check`.
- Grep: Samsung `:9004` and `IDR_N_LP` appear in `docs/live-session.md` and not
  in `docs/ARCHITECTURE.md`.
- Grep: “Operator parity (iOS baseline)” heading is gone from `ANDROID.md`.
- `CLAUDE.md` does not mention `ARCHITECTURE.md` and has no `@import`.
- Pointer table in `AGENTS.md` names every disclosed file in this spec.
- Forbidden paths unstaged.

## Success

An agent starting a chrome change loads **parity** (and **physical**) without
loading JNI or DUML. An agent starting a UDP freeze loads **live-session** and
**watchdog** without loading Operator Setup. A human can onboard from `AGENTS.md`
plus the one pointer that matches their task.

## Later slices (not this PR)

2–3. Parity/performance budgets as living SLOs (this slice only *extracts* the
     contract that already lives in `ANDROID.md`).
4. Security, OSS collaboration, sediment cleanup.
5. UX / FTUE contract for creatives and operators.
6. Agentic execution (task graphs, bounded loops, optional knowledge graph).
