# Native head tracking

Status: **experimental; rapid retargeting and end-to-end AirPods response are
not yet physically qualified**. The initial native command probes established
small yaw/pitch movement and short A→B→C execution on Pocket 4 Pro; they do not
establish continuous tracking latency or behavior on every supported model.

## Shared forward and targets

Calibrate Head Lock keeps its existing meaning: the still head pose and fresh
camera pose are shared forward. It is not a gimbal-rate calibration. Quaternion
nose direction supplies look-right and look-up angles. `HeadTrackNative` clamps
the resulting body-relative pan/tilt to the known reach, then computes native
pitch from the captured attitude i16 `@0`. Display pitch remains negated `@20`;
these are different coordinate references and must not be substituted.

Movable scopes can sit beneath the Calibrate Head Lock / STOP button in portrait
and landscape. Enabling Head Tracking does not shrink their placement area.
The button draws above scopes and keeps its touch target.

The command requests completion in 100 ms. This is a command horizon, **not a
measured end-to-end latency guarantee**. Programmed paths also have no artificial speed ceiling. Firmware response to continuous replacement determines
actual lag, smoothing and achievable speed. Roll remains readout only.

Pan uses the reachable arc from −48° through 0° to +225° (raw −135°),
crossing the ±180° representation boundary without jumping across the stops.
Tilt targets are limited to **−44° through +70°** in display/look-up coordinates.
Native pitch has a different reference; its ±180° encoding range is not the
physical tilt range. Measured angles remain unclipped, so an out-of-range pose
cannot masquerade as a valid endpoint. Capture and dispatch validate bounds.

## Freshness and control ownership

Core Motion measurement timestamps, not callback delivery times, determine
sample freshness. Apple's [timestamp reference](https://developer.apple.com/documentation/coremotion/cmlogitem/timestamp)
defines the timestamp as seconds since device boot. Measurements older than
200 ms are rejected, including repeated reads of cached samples. Camera pose
receipt age must remain within 300 ms. Callback generations prevent a stopped
or disconnected motion stream from overwriting a newer stream.

The iOS bridge owns one motion request while permission or the first sample is
pending. Core Motion's active flag does not identify an outstanding start;
repeated view updates cannot replace its callback generation. Stop also cancels
a pending request. Permission denial, unavailable motion, startup silence and
motion errors have distinct guidance. After an authorized stream has stayed
silent for five seconds, Calibrate explicitly restarts it. Errors also require
an explicit retry. Missing samples alone do not establish whether headphones
are in the wearer's ears.

Head driving uses a session token. Manual control, programmed movement and
inactive scenes cancel it; old updates and stops cannot affect a newer owner.
Cancellation clears pending native targets and serializes STOP on the UDP
queue before takeover commands. A not-ready socket cannot queue a stale head
STOP to interrupt a later controller. Last issued head targets have a bounded
100 ms requested horizon if the connection is lost before STOP can be sent.

## Transport and verification

`GimbalNativeTargetStream` is a latest-target mailbox, not a replay queue.
Identical quantized targets are suppressed so a stationary target can finish.
The existing ACK queue drains it with a 40 ms minimum interval; the 25 ms ACK
timer means typical wire cadence is 20 Hz. Unavailable sockets do not consume
fresh targets or accumulate native writes in the network layer. Pending
samples expire after 200 ms. The existing 40 Hz window ACK remains unchanged.

Core tests cover native mapping and reach, angle wrapping, stale source samples,
callback generations, owner changes, duplicate suppression, bounded emission,
and unavailable-socket recovery. Physical verification must measure step and
sinusoidal head inputs, stationary jitter, angular lag, stop/takeover behavior,
and live-view FPS/ACK health. Synthetic inputs through a real phone/camera test
the motor/transport path; wearer tests are still needed across the full AirPods
response and recovery matrix. A short September 12 wearer capture sustained
native targets alongside roughly 25 FPS video after successful calibration;
it also exposed a permission-pending startup ownership failure. Bridge tests
cover repeated pending starts, stop during permission, stale callbacks, explicit
retry and permission/error guidance. One `head-motion` diagnostic row per second
records request generation, platform state, accepted/rejected counts and source
age, without identities or head angles.
