# Nano cadence: socket QoS evidence

Date: 2026-09-09. Surface: engineering docs. Bounded read-only investigation;
no hardware or networking parameters changed.

## What iOS service class can change

Apple defines `NWParameters.ServiceClass` primarily as prioritization of
**transmitted** traffic on the underlying connection. It explicitly cautions that
this does not necessarily change received packet priority. The default is
`bestEffort`; Apple recommends a different class when the use case or test results
justify it. [Apple ServiceClass documentation](https://developer.apple.com/documentation/network/nwparameters/serviceclass-swift.enum).

`interactiveVideo` describes low-delay, low-loss, constant-rate traffic, but Apple
also says it does not support high throughput. This is a candidate to measure for
the app's outgoing datalink acknowledgments, not an established fix for camera
video arrival gaps. It does not instruct the Nano to transmit at a different
cadence. [Apple interactiveVideo documentation](https://developer.apple.com/documentation/network/nwparameters/serviceclass-swift.enum/interactivevideo).

Do not substitute Wi-Fi Aware real-time performance APIs for infrastructure Wi-Fi
settings: the camera connection under investigation is ordinary Wi-Fi.

## Current app configuration

At inspection, `DatalinkDriver.wifiUDP()` passes default `NWParameters.udp` through
`cameraParameters`, which selects the local endpoint/interface, permits local
endpoint reuse, and excludes cellular. It does not assign `serviceClass`. The
receive dispatch queue also has no explicit execution QoS. Network traffic
service class and dispatch execution QoS are different settings; neither absence
establishes the cause of a stutter. [DatalinkDriver](../ios/OpenPocketCine/DatalinkDriver.swift).

TCP `noDelay` disables Nagle's algorithm for TCP. It cannot directly change UDP
video delivery or the UDP ACK loop. [Apple TCP options](https://developer.apple.com/documentation/network/nwprotocoltcp/options).

## What the inspected Mimo artifact establishes

The official Android native artifact identified in the [Wi-Fi role review](research-osmo-wifi-role-external.md)
contains a `Udp_Create` helper. Its inspected socket options configure receive
and send **timeouts**, not receive-buffer size or IP traffic class. Its matching
receive helper can update the receive timeout. No supported Mimo `IP_TOS` value
or Nano-specific receive-buffer setting was established in this bounded pass.

This does not prove Mimo leaves every socket at defaults: other native helpers
and an Android socket bridge exist. Android APK behavior also does not establish
the options used by iOS Mimo. Proprietary disassembly stays local; only these
derived observations are recorded here.

## Interpretation and useful measurement

The parent investigation reports matching packet and completed-frame gaps with
no incomplete frames or display backpressure, plus a separate main-actor pause
while adding another camera. Those observations do not identify one shared cause.
A receive-callback gap alone also cannot distinguish a radio arrival gap from
delayed delivery of callbacks.

The parent capture reports different existing camera IP traffic markings and
unmarked app ACKs. That is evidence of a marking difference, not evidence of its
effect on this network. RVI timestamps also showed simultaneous gaps on both
camera flows that did not match on-device cadence; do not use those apparent
capture gaps as wire-timing truth without validating the capture clock/delivery.

The next useful comparison is synchronized packet capture and ACK-departure
timing for Mimo versus OpenPocketCine using the same Nano/network. Check whether
camera packet bursts follow late ACKs, and compare IP traffic markings on both
directions. A service-class trial should measure those outcomes and throughput;
it should not be reported as the solution merely because the API name says video.

## Follow-up: presentation pacing

No Nano-specific Mimo jitter-buffer duration or active presentation scheduler was
established in the native artifact. Its generic frame-queue implementation pops
a mutex-protected FIFO; that alone proves neither timed rendering nor use by Nano
live view. Android library symbols also cannot establish iOS Mimo presentation
behavior. Do not describe a proposed buffer as matching Mimo.

OpenPocketCine's inspected decoder sets `DisplayImmediately`. Apple documents that
this asks the display layer to show a decoded frame immediately, replacing prior
enqueued images regardless of their timestamps. Without that attachment,
presentation uses the sample timestamp and the renderer's timebase. Thus a burst
of complete, consecutive frames can still look uneven even when no transport
frames are missing. [Apple enqueue semantics](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/enqueue(_:)),
[display timebase](https://developer.apple.com/documentation/avfoundation/avsamplebufferdisplaylayer/controltimebase).

The reported 25 fps cadence implies a 40 ms frame period. An 80–98 ms arrival gap
contains 40–58 ms beyond one nominal period, but **this does not establish a
sufficient fixed buffer**. Derive a trial from consecutive-frame arrival times:
for frame index `i`, compare arrival `a[i]` with the nominal schedule
`a[0] + (i - i[0]) * 40 ms`. The distribution and sustained growth of that
lateness reveal whether a small playout delay could absorb observed bursts or
would merely postpone an eventual underrun. Prefer camera presentation times
when their meaning is verified, and fit long-window cadence to avoid clock drift.

Any pacing experiment needs a bounded queue, an explicit latency budget, and an
underrun/discontinuity policy. A roughly 0.86 s recording transition should remain
a distinct event rather than defining a permanent near-second preview delay.
Test smoothness and control-to-picture latency together; no particular buffer
duration is established by this research.
