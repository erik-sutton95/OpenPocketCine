// The second-screen relay wire (version 1 framing, messages, frame blob, version check), the
// control lease and relay pacing policy live in OpenCineCore's OpenCineRelay. Re-exported so
// app call sites keep importing only this module. Sockets, Bonjour, the encoder and the
// passcode keychain stay in the iOS shell.
@_exported import OpenCineRelay

extension WatcherRelayJoin {
    /// This app's version-mismatch copy, sent to the watcher in `joinDenied`.
    public static func hostAccepts(hello: WatcherRelayHello, requiredPasscode: String)
        -> Result<Void, WatcherRelayJoinDenied>
    {
        hostAccepts(
            hello: hello, requiredPasscode: requiredPasscode,
            versionMismatchReason: "This OpenPocketCine build cannot watch that feed.")
    }
}
