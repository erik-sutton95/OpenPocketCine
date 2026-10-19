// The second-screen relay wire (version 1 framing, messages, frame blob, version check), the
// control lease and relay pacing policy live in OpenCineCore's OpenCineRelay. Re-exported so
// app call sites keep importing only this module. Sockets, Bonjour and the encoder come from
// OpenCineRelayApple; the passcode keychain stays in the iOS shell.
@_exported import OpenCineRelay

extension WatcherRelayJoin {
    /// The host's version-mismatch copy, sent to the watcher in `joinDenied`.
    public static let versionMismatchReason = "This OpenPocketCine build cannot watch that feed."

    /// The watcher's own copy when the host's hello outran this build: the baseline instructed the
    /// operator to update both devices, because the mismatch can be either end.
    public static let watcherVersionMismatchReason =
        "Update OpenPocketCine on both devices to watch this feed."

    public static func hostAccepts(hello: WatcherRelayHello, requiredPasscode: String)
        -> Result<Void, WatcherRelayJoinDenied>
    {
        hostAccepts(
            hello: hello, requiredPasscode: requiredPasscode,
            versionMismatchReason: versionMismatchReason)
    }
}
