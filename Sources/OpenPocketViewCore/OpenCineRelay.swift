// The second-screen relay wire (version 1 framing, messages, frame blob, version check), the
// control lease and relay pacing policy live in OpenCineCore's OpenCineRelay. Re-exported so
// app call sites keep importing only this module. Sockets, Bonjour and the encoder come from
// OpenCineRelayApple; the passcode keychain stays in the iOS shell.
@_exported import OpenCineRelay

extension WatcherRelayJoin {
    /// This app's version-mismatch copy, sent to the watcher in `joinDenied`.
    public static let versionMismatchReason = "This OpenPocketCine build cannot watch that feed."

    public static func hostAccepts(hello: WatcherRelayHello, requiredPasscode: String)
        -> Result<Void, WatcherRelayJoinDenied>
    {
        hostAccepts(
            hello: hello, requiredPasscode: requiredPasscode,
            versionMismatchReason: versionMismatchReason)
    }
}
