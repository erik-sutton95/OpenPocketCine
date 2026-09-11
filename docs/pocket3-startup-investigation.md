# Pocket 3 startup stall investigation

Surface: **docs**. Investigation dated **2026-09-11**; this is evidence and a
follow-up plan, not a replacement for the
[connection reliability contract](connection-reliability.md).

## Current status

**Currently not reproducible; cause unconfirmed.** On 2026-09-11, the operator
reported that the cold-boot stall appeared gone and could no longer be
reproduced. This adds an operator retest report to the captured warm-session
evidence below; it does not identify which change or condition resolved the
symptom. No cold-boot-specific production fix was made by this investigation.
Retain the historical evidence and resume fault isolation if the stall returns.

## What the failing session establishes

The reported symptom is a first connection that shows picture, fails to respond
to controls, then freezes picture before recovering about 20–30 seconds later.
The saved iOS journal corroborates control-reply timeouts before picture loss.
Times below are relative to the
initial picture/control startup at 2026-09-10 23:18:54 UTC.

| Elapsed | Journal evidence |
| --- | --- |
| 0s | Picture path starts; tracked audio GET is sent. |
| 3s | First control timeout; further GET timeouts recur at three-second intervals. |
| About 11s | Last picture/video packet, inferred from subsequent age counters. |
| 16s, 21s | Watchdog stream enables do not restore picture. |
| 26s | UDP rebuild preserving the existing session does not recover it. |
| 34s | Recovery starts a full new handshake. |
| 35s | Audio/focus replies arrive and the decoder presents picture. |
| 37s | The journal reports about 25fps. |

The recovery ladder explains roughly **24 seconds without picture**. It does
not establish why control traffic stopped being useful before the freeze.
Status age remained about 0–0.1 seconds before the UDP rebuild, so this was a
partial failure rather than complete loss of incoming UDP traffic.
The sequence is consistent with a datalink/session problem; it does not prove
a decoder fault, camera warm-up requirement or specific ACK error.

## What was tested afterwards

Packet capture covered an in-app reconnect and an app relaunch. Both produced
initial command sequences matching the camera's initial window, and control
replies flowed. The reconnect sustained about 25fps for at least a minute. The
relaunch reached picture after the existing 1080p/25 → 4K/25 recovery poke and
then sustained about 25fps. Neither reproduced the reported control stall.

A final check used installed iOS **0.1.0 (99)** on the same powered camera.
The initial 4K/25 join sustained about 25fps with no control timeout or video
stall in the saved journal. A later 2.7K/25 app relaunch also returned to healthy
picture and control replies. The app selected 2.7K/25, started and stopped a short recording,
and retained 2.7K/25 plus D-Log M after relaunch/reconnection. The monitor then
returned to 4K/25. These are warm-session observations, not a cold-boot fix.

An app relaunch is **not a camera cold boot**. The initial file named
`cold-start.pcapng` begins in an already healthy session; its filename is an
experiment intent, not evidence that the failed boot was captured. Private
captures and the complete journal remain outside git.

## Candidate startup seam

The iOS `DatalinkDriver` can observe the handshake flag on the UDP receive queue
before the main-actor ingest task has updated `camChannel`. Normal SoftAP open
uses that channel to seed command sequencing. Station open can instead use the
separately captured 34-byte initial window. Also, the post-handshake
`primeWireSeqs()` call clears ACK-window state that the receive queue may already
have learned.

These are concrete ordering risks in the inspected implementation, but the
failed connection lacks the packet evidence needed to attribute this incident
to either one. The successful warm takes do not discriminate between them.

## Proof and fix criteria if the stall returns

1. Start capture before a physical camera power-off/power-on and app connection.
   Preserve the first handshake reply, initial 34-byte window, first command,
   all three ACK groups, control timeouts and first/last picture times.
2. Compare failed and successful starts on the same firmware. Determine whether
   commands were sent from the wrong initial sequence, ACK state was rewound,
   or the transport failed for another reason.
3. If startup ordering is confirmed, make readiness explicit: acquire the
   required initial window within a bounded deadline, preserve received ACK
   state, and only then register/subscribe/enable. Test delayed and reordered
   arrivals, cancellation and sequence wraparound.
4. Verify on physical hardware for each changed shell, including warm reconnect
   and foreground return. Preserve enable-once behavior and the existing ACK
   budget; shortening watchdog timers alone does not fix the initiating fault.

No production fix is claimed by this investigation. The unchanged core baseline
passed 753 tests in 72 suites. The broader
[Pocket 3 survey](https://openpocketcine.app/docs/protocol/pocket3/) records the
separate Mimo controls and protocol findings gathered while the camera remained
available.
