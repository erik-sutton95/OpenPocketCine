# Shared Monitor Engine — Multi-Brand Architecture

**Status:** design intent (2026-09-06)
**Audience:** human maintainers + coding agents (Grok / Cursor / CLI)
**Related products today:** OpenPocketCine (DJI Osmo), OpenZCine (Nikon Z)
**Planned adapters later:** Insta360 (e.g. Luna Ultra), Fujifilm, others

This document is the source of truth for *how* we scale to many camera brands without multiplying full apps. If an agent is about to fork UI, media, scopes, or delivery per brand: **stop and re-read this file.**

---

## 1. One-sentence mission

**Many brand storefronts, one monitoring engine, one delivery stack; only the camera connection/protocol adapter differs per brand, with capability flags driving UI differences (e.g. gimbal stick).**

---

## 2. Goals

1. **Identical operator experience** across brand apps for:
   - Live-view monitoring tools (waveform, RGB parade, histogram, vectorscope, false color, zebras, peaking, traffic lights, guides, LUTs, layout chrome)
   - Playback and media management (browse, cache, star/delete where supported, review assists)
   - Cloud **delivery** destinations (Frame.io Platform API v4, Google Drive, Dropbox, and future connectors) — same UX and pipeline shape
2. **Separate brand apps** (bundle id, name, icon, site, TestFlight/Play listing) so a camera maker can collaborate on “the open monitor for *our* cameras” without co-signing a multi-brand competitor on the home screen.
3. **Solo-maintainer scalability:** adding a brand is mostly a new **CameraBackend adapter** + thin branded shell, not cloning OpenZCine/OpenPocketCine again.
4. **Stay native** for the live path: Swift portable core + SwiftUI iOS shell + Kotlin/Compose Android shell (and existing Swift-for-Android / JNI patterns). **Do not rewrite to Flutter** for this architecture.
5. **Open source** (Apache-2.0 style as today): no secrets in git; Frame.io / OAuth credentials stay local/CI-injected.

## 3. Non-goals (explicit)

| Non-goal | Why |
| --- | --- |
| One App Store app that lists every brand | Alienates brand partnership optics; SEO/press per brand still valuable |
| Flutter / React Native rewrite | Live decode + GPU scopes + SoftAP/BLE need fat native plugins; erases the win |
| Per-brand forks of media / scopes / Frame.io | That is the maintainability failure mode we are escaping |
| Calling the product “Camera to Cloud” / C2C | Adobe/Frame.io: that name is their **device** program/API. We use **Frame.io delivery** / Platform API v4. |
| Implementing Insta360/Fuji backends in the first migration PR | Extract shared engine + prove Osmo + Nikon adapters first |
| Perfect pixel parity with every first-party OEM app | We match *our* monitor UX across brands, not Mimo/Nikon app clones |

---

## 4. Vocabulary (use these words in code and docs)

| Term | Meaning |
| --- | --- |
| **Brand app** | Thin storefront: OpenPocketCine, OpenZCine, future Open… for Insta360/Fuji. Identity + adapter wiring. |
| **Shared monitor engine** | Packages/modules used by every brand app: scopes, assists, layout policy, media, playback, LUT bake, delivery, settings chrome patterns, diagnostics redaction. |
| **CameraBackend** | Per-brand (or per-protocol-family) adapter: discovery, connect, live frames, controls, clip catalog/download, disconnect/recover. |
| **Capability** | Boolean/enum flags the backend advertises; UI shows/hides features (gimbal stick, iris, timecode, SoftAP hop, etc.). |
| **Platform shell** | iOS SwiftUI or Android Compose: sockets, BLE, Wi‑Fi join, decoders, GPU views, Keychain/Keystore, lifecycle. |
| **Delivery** | Upload/share pipeline after media is local (Frame.io, Drive, Dropbox, system share, Photos). Not “C2C”. |
| **Internet hop** | Leave camera AP → use cellular/home Wi‑Fi for delivery/auth → rejoin camera. Shared behavior. |

---

## 5. Architectural diagram

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ Brand apps (thin)                                                       │
│  OpenPocketCine │ OpenZCine │ OpenInsta… │ OpenFuji…                    │
│  - bundle id, icons, site links, legal copy variants                    │
│  - registers ONE CameraBackend + brand theme tokens                     │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ depends on
┌───────────────────────────────▼─────────────────────────────────────────┐
│ Shared monitor engine (packages)                                        │
│  MonitorUI  │  Scopes/Assists  │  Media+Playback  │  Delivery           │
│  Settings patterns  │  Diagnostics policy  │  Capability-driven chrome  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ talks to
┌───────────────────────────────▼─────────────────────────────────────────┐
│ CameraBackend protocol (portable)                                       │
│  connect / live frames / controls / catalog / download / capabilities   │
└───────────────┬─────────────────┬─────────────────┬─────────────────────┘
                │                 │                 │
        ┌───────▼──────┐  ┌───────▼──────┐  ┌───────▼──────┐
        │ OsmoAdapter  │  │ NikonAdapter │  │ LunaAdapter  │  …
        │ (DUML/BLE/   │  │ (opcodes/PTP │  │ (SDK/loaner) │
        │  SoftAP/HEVC)│  │  /feed)      │  │              │
        └──────────────┘  └──────────────┘  └──────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────────┐
│ Platform shells (I/O only — no brand business forks)                    │
│  iOS: CoreBluetooth, NEHotspotConfiguration, VideoToolbox, Metal, …     │
│  Android: WifiNetworkSpecifier, MediaCodec, GLES, JNI to Swift core … │
└─────────────────────────────────────────────────────────────────────────┘
```

**Rule for agents:** business/protocol *policy* that is brand-agnostic stays in the shared engine. Wire codecs and OS calls stay in shells. Brand-specific *bytes on the wire* stay in adapters.

---

## 6. Layering rules (hard)

### 6.1 Shared engine MUST contain

- Scope and assist math / presentation policy (what to draw, when; feed present hygiene where already portable)
- Monitor layout policy and capability-gated control clusters (gimbal stick appears iff capability)
- Media library model: clip identity, cache state, playback session orchestration (not the OEM file transfer protocol)
- LUT load/preview/bake orchestration (Metal/GLES backends remain shell-owned implementations behind a shared interface)
- Delivery coordinator: destination picker, hop gate, progress, cancel, summary toasts
- Frame.io Platform API v4 client planning + OAuth PKCE helpers (as today in OpenZCine core); tokens never logged
- Future Drive/Dropbox connectors as siblings of Frame.io under the same delivery abstraction
- Diagnostics redaction / report shape
- Operator-facing strings that are brand-agnostic (brand name injected via tokens)

### 6.2 CameraBackend MUST contain (per brand)

- Discovery / pairing (BLE, USB, OEM SDK, …)
- Network path to camera (SoftAP join, binding, DHCP readiness) *as required by that brand*
- Live-view enable, codec, frame delivery into the shared feed sink
- Camera controls mapping (ISO, shutter, iris, WB, record, zoom, gimbal, …) → shared control model
- Clip catalog + download/cache into the shared media cache layout
- Error/recover semantics specific to that protocol
- **Capability set** for the connected body (and updates when body changes)

### 6.3 Brand app MUST contain only

- Xcode/Gradle app target, bundle id, icons, display name
- Which backend factory to construct
- Optional partner-required legal/about copy
- Deep links / URL schemes unique to that app (e.g. Frame.io redirect scheme per Adobe app credential)
- CI/TestFlight/Play project wiring

### 6.4 Brand app MUST NOT

- Reimplement scopes, media grid, or Frame.io upload
- Fork delivery hop logic
- Special-case “if DJI …” inside shared UI (use capabilities instead)
- Commit OAuth client secrets or API keys

---

## 7. `CameraBackend` contract (agent-facing sketch)

Agents implementing or refactoring should aim for a portable Swift protocol (names can be refined, responsibilities must not). Kotlin/Android calls the same ideas via facade/JNI where the project already does.

```swift
public struct CameraCapabilities: Equatable, Sendable {
    public var supportsGimbalStick: Bool
    public var supportsHeadTrack: Bool
    public var supportsIris: Bool
    public var supportsZoom: Bool
    public var supportsTimecode: Bool
    public var supportsClipDelete: Bool
    public var supportsClipStar: Bool
    public var requiresCameraAccessPoint: Bool
    public var requiresInternetHopForDelivery: Bool
    public var liveCodec: LiveCodecHint  // hevc, avc, other
    // extend carefully; prefer additive flags over brand enums in UI code
}

public protocol CameraBackend: AnyObject, Sendable {
    var brandID: String { get }           // "osmo" | "nikon" | "insta360" | "fujifilm"
    var capabilities: CameraCapabilities { get }

    func startDiscovery() async throws
    func connect(to device: DiscoveredDevice) async throws
    func disconnect(reason: DisconnectReason) async

    /// Push decoded or decode-ready live frames into the shared feed sink.
    var liveFeed: any LiveFeedSourcing { get }

    func apply(_ control: CameraControlCommand) async throws
    func currentStatus() -> CameraStatusSnapshot

    func listClips() async throws -> [CameraClipDescriptor]
    func downloadClip(_ id: ClipID, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    // optional delete/star if capabilities allow
}
```

### 7.1 Capability-driven UI (required pattern)

```text
WRONG:  if brand == .dji { showJoystick() }
RIGHT:  if capabilities.supportsGimbalStick { showJoystick() }
```

Same for iris wheels, head-track, timecode chips, SoftAP-only warnings, etc.

When a backend cannot support a shared feature yet, **hide or disable with a clear reason** — do not fork a second media screen.

---

## 8. Shared delivery architecture

### 8.1 Product language

- Say **Frame.io delivery**, **upload to Frame.io**, **cloud delivery**.
- Do **not** say Camera to Cloud / C2C in user-facing copy, READMEs, or App Store text (Adobe device-program term).

### 8.2 Pipeline (identical across brands)

```text
Select clips (media grid / player)
  → ensure cached locally (backend.downloadClip)   // may need camera path
  → optional LUT bake / export prepare            // shared
  → if requiresInternetHopForDelivery && on camera AP:
        explicit consent → hop → wait for internet
  → Destination.connect + upload                  // Frame.io | Drive | Dropbox | …
  → summary toast; persist per-clip delivery state
  → if hopped: rejoin camera via backend connect path
```

Progress survives navigation via a shared `MediaDeliveryCoordinator` (pattern already in OpenZCine / OpenPocketCine).

### 8.3 Destination plugin interface

```swift
public protocol DeliveryDestination {
    var id: String { get }          // "frameio" | "google_drive" | "dropbox" | "system_share" | "photos"
    var isConfigured: Bool { get }  // fail closed if keys missing
    var isSignedIn: Bool { get }

    func signIn() async throws
    func signOut() async
    func listTargets() async throws -> [DeliveryTarget]  // projects/folders
    func upload(file: URL, to: DeliveryTarget, progress: @escaping @Sendable (Double) -> Void) async throws -> DeliveryReceipt
}
```

Frame.io today: Adobe IMS OAuth 2.0 PKCE (Native App, no client secret), Create File → pre-signed S3 PUTs → poll `upload_complete`. Drive/Dropbox: add as new `DeliveryDestination` implementations; **do not** copy-paste hop/coordinator logic.

---

## 9. Platform shells

| Concern | Shared policy | Shell I/O |
| --- | --- | --- |
| Live present hygiene | portable policy types | Metal / GLES / player hosts |
| SoftAP / Wi‑Fi | portable readiness gates where possible | `NEHotspotConfiguration` / `WifiNetworkSpecifier` |
| Decode | codec hints from backend | VideoToolbox / MediaCodec |
| Secrets | never log tokens | Keychain / Keystore |
| Frame.io / OAuth UI | PKCE helpers in engine | `ASWebAuthenticationSession` / Custom Tabs |

**Do not** introduce a JS runtime. Keep Lucide/SVG icon vendor pattern unless intentionally redesigned once in the shared engine.

---

## 10. Repository layout (target)

Prefer a **monorepo** long-term so agents cannot drift packages. Until migration completes, a multi-repo setup with a shared package is acceptable if versioned strictly.

### 10.1 Proposed monorepo sketch

```text
OpenCaptureMonitor/   # working title for the monorepo — rename when the umbrella engine name is chosen
  Packages/
    MonitorEngine/           # scopes, layout policy, media models, delivery coordinator
    CameraBackend/           # protocol + shared types (capabilities, clip descriptors)
    FrameioKit/              # Platform API v4 + PKCE planning (optional split)
    DeliveryKit/             # destination protocol + hop orchestration hooks
  Adapters/
    OsmoDUML/
    NikonZ/
    Insta360/                # later
    Fujifilm/                # later
  Apps/
    OpenPocketCine/          # iOS + Android app targets
    OpenZCine/
    …
  docs/
    SHARED-MONITOR-ENGINE.md  # this file
    PARITY.md                 # operator-visible sameness across brands
  Tests/
```

### 10.2 Until monorepo exists

1. Extract shared Swift packages from the stronger shared surface (often OpenZCine Frame.io + media delivery docs; OpenPocketCine SoftAP/DUML policy).
2. Both brand repos depend on the same package versions (SPM path or tagged).
3. Agents MUST update the shared package for cross-brand features, then bump both apps — never only one app’s copy.

---

## 11. Migration plan (phased — agents follow in order)

### Phase 0 — Freeze the wrong path

- No Flutter spike for production.
- No new per-brand Frame.io clone.
- No user-facing “Camera to Cloud” copy (fix OpenZCine README etc. when touching those files).

### Phase 1 — Document + capability inventory

- Inventory features in OpenPocketCine vs OpenZCine.
- Mark each: Shared engine / Osmo adapter / Nikon adapter / Shell-only.
- List capability flags needed for current UI differences (gimbal stick, head track, SoftAP hop, etc.).

### Phase 2 — Extract Delivery + Media orchestration

- Move delivery coordinator + Frame.io client planning into shared packages.
- Both apps call shared code; brand apps only supply OAuth plist/gradle config.
- Prove: identical Frame.io upload behavior on Osmo and Nikon builds.

### Phase 3 — Extract Monitor scopes/assists/layout policy

- Unify scope/assist entry points and layout policy.
- Wire capability gates for gimbal cluster.

### Phase 4 — Formalize `CameraBackend`

- Wrap existing Osmo session as `OsmoAdapter`.
- Wrap existing Nikon session as `NikonAdapter`.
- Brand apps construct adapter at launch; no protocol code in UI views.

### Phase 5 — Thin brand apps

- Strip duplicated SwiftUI/Compose screens that are now shared.
- Keep storefront identity.

### Phase 6 — Add brand N (Insta360 / Fuji)

- New adapter package + new thin app target.
- Reuse engine; only implement backend + capabilities + credentials.
- Partnership/SDK/loaner work is **out of band** (docs/outreach), not a reason to fork UI.

**Done when:** a coding agent can add a stub backend + empty brand app and inherit monitoring + media + delivery UI without copying screens.

---

## 12. Testing requirements

| Layer | Required tests |
| --- | --- |
| Capabilities | UI/store logic never switches on brand enum for features that are capability-gated |
| Frame.io / delivery | PKCE + request planning unit tests (no secrets); hop consent state machine tests |
| Adapters | Protocol unit tests with recorded fixtures where possible; hardware tests marked `[VERIFY-ON-HW]` |
| Parity | Operator-facing checklist: same monitor tools and delivery options visible when capabilities allow |

Agents: prefer extending existing `Frameio*Tests` / parity docs over new parallel frameworks.

---

## 13. Security & open-source constraints

- OAuth client IDs / redirect URIs: gitignored local config (xcconfig / `*.local.properties`), CI secrets for release builds.
- No static Frame.io **device** `client_secret` in the open-source apps (that path is Adobe’s C2C device program and conflicts with OSS). Stay on Platform API v4 user OAuth PKCE unless a future partner agreement explicitly changes this — and even then secrets must not be committed.
- Never log access tokens, refresh tokens, Wi‑Fi passwords, or camera credentials.
- Direct HTTPS to Frame.io / Drive / Dropbox from the device (no proxy that holds user tokens) unless a documented, user-visible exception exists.

---

## 14. Partnership posture (product, not code)

- **External story:** each brand gets its own app and identity; under the hood they share an open monitoring engine.
- **Internal story:** shared engine + adapters.
- Brand collab may require NDA, SDK, hardware loan — that does not justify duplicating the monitor UI.
- If a partner *requires* exclusive binary branding, the thin app model already satisfies that.

---

## 15. Decision log

| Date | Decision |
| --- | --- |
| 2026-09-06 | Keep separate brand apps for partnership optics |
| 2026-09-06 | Share monitor tools, media/playback, and cloud delivery across brands |
| 2026-09-06 | Only connection/protocol (+ capabilities) differ per brand |
| 2026-09-06 | Reject Flutter rewrite for this problem |
| 2026-09-06 | Reject single multi-brand consumer app *as the only surface* (skins/apps stay separate) |
| 2026-09-06 | Prefer capability flags over brand switches in UI |
| 2026-09-03 | Do not use “Camera to Cloud” / C2C in product copy; Frame.io = Platform API v4 delivery |

---

## 16. Instructions for coding agents (checklist)

When implementing a feature, the agent MUST:

1. Ask: does this belong in **shared engine**, **adapter**, or **brand app identity**?
2. If it is scopes, media, playback, LUT bake, hop, Frame.io/Drive/Dropbox → **shared engine**.
3. If it is DUML / Nikon opcodes / OEM SDK connect → **adapter**.
4. If UI differs by camera → add/use a **capability**, do not `switch` on brand.
5. Preserve OpenPocketCine / OpenZCine storefronts unless the maintainer explicitly asks to rename/merge listings.
6. Use wording **Frame.io delivery**, never Camera to Cloud.
7. Not introduce Flutter/RN.
8. Not commit secrets.
9. Update this document’s decision log if the agreed direction changes.
10. Prefer extracting existing code over rewriting from scratch.

When unsure, prefer **shared** over **duplicated**.

---

## 17. Open questions (product decisions — do not block Phase 1–2)

- Final umbrella name for the monorepo / engine package (OpenCapture, etc.).
- Whether Android for every brand ships in lockstep with iOS for each adapter.
- Drive/Dropbox priority order after Frame.io.
- Whether Insta360 uses public panoramic SDK vs separate Luna path (loaner/SDK dependent).
- Monorepo now vs shared SPM package across two GitHub repos first.

---

## 18. Success metric

A solo maintainer can ship a new camera brand’s TestFlight by:

1. Implementing/adapting a `CameraBackend`
2. Filling capabilities
3. Creating a thin app target with icons + OAuth config
4. Inheriting monitoring, media, and delivery unchanged

If step 4 requires copying SwiftUI/Compose screens, the architecture is not done.
