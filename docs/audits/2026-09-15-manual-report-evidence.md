# Manual report evidence audit

The submitted development-build diagnostic attachment exposed a report-budget
problem: the 32,000-character prefix ended inside historical MetricKit JSON,
before the recent journal. Its environment snapshot described report time, not
the failure. A MetricKit collection callback stack is not the crash stack.
No private report contents or images are reproduced here.

## Changes

- The native form uses a bounded manual report with reserved space for recent
  activity, typed incident/session summaries and recent faults. Complete large
  extras may be omitted with an explicit notice; they are not silently cut mid-JSON.
- Generation time and report-time environment are distinguished from incident
  timestamps. The local full diagnostic export remains available.
- MetricKit receipt is an informational notice. The original payload retains
  its original diagnostic stack; the collector callback no longer adds an
  unrelated fault stack.
- Manual iOS feedback uses the same release/build and environment convention
  as automatic reports, plus the configured source revision when available.
- Explicitly chosen images accompany manual feedback only. Up to three bounded
  JPEGs are prepared from pixels, previewed and removable before Send. No source
  filename or location metadata is forwarded, and no automatic screenshot occurs.

## What each source establishes

| Source | Useful evidence | Limit |
| --- | --- | --- |
| Manual report | Operator description, optional images and reply address, report-time environment, recent journal and stored incident summaries | The description alone does not establish a crash or identify its cause. |
| Typed feed incident | Packet/AU/decode/present progress, lifecycle context, repair attempts and outcomes, incident/build identifiers | Only implemented trigger/stage instrumentation is covered; counters are not physical display scanout. |
| Native Sentry crash/hang | Native failure or hang stack, OS/device and build context, permitted breadcrumbs | Requires opt-in, eventual internet delivery and matching debug symbols for the exact binary. |
| MetricKit/local full export | OS-provided historical payloads and fuller local history | Delivery may be delayed; collection time is not occurrence time. |
| Session summaries | Observed exposure, incident count and session outcome | Reporting-enabled sessions are not the whole installed population. |

Ordinary logged errors do not all become separate Sentry issues. A manual report
is not automatically linked to a particular native crash. Compare occurrence
window, release/build and available incident IDs before assigning a cause.

## Remaining qualification

Development iOS manual text/diagnostic delivery and earlier deliberate native
crash symbolication were verified. This does not qualify every release binary:
release CI must upload matching symbols, and development rebuilds that reuse a
version/build number may have different binary UUIDs. Physical Android delivery,
release rollout/privacy operations and hosted selected-image delivery remain
separate checks. See [Sentry deployment](../sentry-deployment.md),
[privacy operations](../sentry-privacy-operations.md) and [parity](../PARITY.md).
