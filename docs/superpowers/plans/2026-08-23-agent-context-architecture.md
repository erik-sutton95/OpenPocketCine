# Agent context architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the thin `AGENTS.md` index plus disclosed `CONTEXT.md`, `docs/live-session.md`, and `docs/PARITY.md`, with Architecture and Android split so each fact has one home.

**Architecture:** Always-loaded rules stay in `AGENTS.md`. Durable seams stay in `docs/ARCHITECTURE.md`. Live UDP/decoder gotchas move to `docs/live-session.md`. Operator-visible contract moves to `docs/PARITY.md`. `ANDROID.md` keeps JNI/build/I/O only. Client stubs point at `AGENTS.md` with no `@import`.

**Tech Stack:** Markdown in-repo; verification is `just check` plus the spec’s grep ledger.

**Spec:** `docs/superpowers/specs/2026-08-23-agent-context-architecture-design.md`

## Global Constraints

- Docs-only. No Swift, Kotlin, Gradle, or `justfile` changes unless a link check requires it.
- One home per fact: after a move, delete the old copy.
- `AGENTS.md` about 90–110 lines. No Architecture `@import` from `CLAUDE.md`.
- Leading words: portable, enable-once, hygiene, parity, physical, seams, JNI, live-session, watchdog, naming, protocol, contributing.
- Do not add Cursor/Copilot/Gemini/Windsurf instruction files.
- Branch: `docs/agent-context-architecture`. Conventional Commits. No commits to `main`.

## File map

| File | Role |
| --- | --- |
| `CONTEXT.md` | Glossary only |
| `docs/live-session.md` | Datalink/decoder runbook |
| `docs/ARCHITECTURE.md` | Durable seams (slim) |
| `docs/PARITY.md` | Operator-visible contract |
| `ANDROID.md` | Android build/JNI/I/O (slim) |
| `AGENTS.md` | Always-loaded index |
| `CLAUDE.md`, `CODEX.md`, `GROK.md` | Pointer stubs |
| `CONTRIBUTING.md` | One pointer sentence |

---

### Task 1: Glossary

**Files:**

- Create: `CONTEXT.md`

- [ ] **Step 1: Write `CONTEXT.md`** using the spec’s term table (Core through Portable). Format: heading, one-sentence purpose, `## Language`, each term as `**Term**:` + `_Avoid_:`.
- [ ] **Step 2: Confirm every spec term is present** (`rg -c '^\*\*(Core|Shell|Facade|Spine|SoftAP|Datalink|Enable-once|Watchdog|Chrome|Parity|Assist|Physical|Hygiene|Portable)\*\*'` → 14).
- [ ] **Step 3: Commit** `docs: add CONTEXT.md glossary`

### Task 2: Live-session runbook + slim Architecture

**Files:**

- Create: `docs/live-session.md`
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Write `docs/live-session.md`** with headings 5-tuple, ACK pump, Enable write, Disconnect teardown, Decoder latch, Foreground / SoftAP flap, Pointers. Copy the facts listed in the spec’s live-session section (Samsung `:9004`, `IDR_N_LP`, teardown, `bindProcessToNetwork(null)`).
- [ ] **Step 2: Rewrite `docs/ARCHITECTURE.md`** to the spec’s trimmed layer table, six short spine steps, policy table plus `CameraSetMailbox`, shells-own-I/O paragraph, pointers to live-session / watchdog / parity / ANDROID.md / handbook. Drop `connection-reliability-plan.md` as an architecture pointer.
- [ ] **Step 3: Ledger grep**

```bash
rg '9004|IDR_N_LP' docs/ARCHITECTURE.md   # expect no Samsung story, no IDR_N_LP
rg '9004|IDR_N_LP' docs/live-session.md   # expect both
```

- [ ] **Step 4: Commit** `docs: split live-session runbook from architecture`

### Task 3: Parity contract + slim Android

**Files:**

- Create: `docs/PARITY.md`
- Modify: `ANDROID.md`

- [ ] **Step 1: Write `docs/PARITY.md`** with the spec’s contract table plus a **Chrome metrics** subsection (27/20 pt drums, 0.72 plates, 17.5 dp histogram gutters, 340 dp FORMAT/COLOR host).
- [ ] **Step 2: Slim `ANDROID.md`:** keep build structure, Pocket mapping, do-not-copy, milestone, OpenZCine patterns. Replace “Operator parity (iOS baseline)” with a pointer to `docs/PARITY.md` and short I/O bullets (Connection, Live picture, HUD glass, Assists GPU, Media decode).
- [ ] **Step 3: Ledger grep**

```bash
rg 'Operator parity \(iOS baseline\)' ANDROID.md   # expect no matches
rg 'Must match' docs/PARITY.md                     # expect the contract table
```

- [ ] **Step 4: Commit** `docs: extract operator parity contract from ANDROID.md`

### Task 4: Always-loaded index and stubs

**Files:**

- Modify: `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`
- Create: `CODEX.md`, `GROK.md`

- [ ] **Step 1: Rewrite `AGENTS.md`** in spec section order: identity, stack & paths, hard rules, before you edit, read when, verification, completion, sediment. Drop the meta-check tool list and “Claude Code and Codex only.”
- [ ] **Step 2: Rewrite `CLAUDE.md`** from the spec template (no `@import`). Add `CODEX.md` and `GROK.md` from the same template.
- [ ] **Step 3: Add one sentence** under CONTRIBUTING Code standards: agent instructions live in `AGENTS.md`; do not copy them here.
- [ ] **Step 4: Ledger grep**

```bash
rg '@import|ARCHITECTURE' CLAUDE.md   # expect no matches
rg 'Read when' AGENTS.md
rg 'CONTEXT.md|PARITY.md|live-session.md|feed-watchdog.md|commit-hygiene.md|CONTRIBUTING.md|ARCHITECTURE.md|ANDROID.md|handbook' AGENTS.md
```

- [ ] **Step 5: Commit** `docs: make AGENTS.md a thin pointer index`

### Task 5: Quality gate

- [ ] **Step 1: `just check`**
- [ ] **Step 2: Fix any markdown/typos/link failures from this slice**
- [ ] **Step 3: Confirm spec verification block** (Samsung/`IDR_N_LP` homes, no Operator parity heading, no CLAUDE `@import`, pointer table complete, no forbidden paths staged)
- [ ] **Step 4: Commit** any lint fixes (`docs:` / `chore:`)

Execution for this run: inline in the current session (user asked to continue unattended).
