import Foundation

/// A delayed UI selection belongs to one presentation context. Cancellation is
/// durable even if a sleeping task resumes after that context has reopened.
public struct MonitorDeferredSelection<Context: Equatable> {
    public struct Request: Equatable {
        public let id: UUID
        public let value: String
        public let context: Context
    }

    public private(set) var pending: Request?

    public init() {}

    @discardableResult
    public mutating func schedule(_ value: String, context: Context) -> Request {
        let request = Request(id: UUID(), value: value, context: context)
        pending = request
        return request
    }

    public mutating func cancel() { pending = nil }

    /// Consume at most once, immediately before dispatch. An older completion
    /// cannot clear a newer choice; unavailable or stale choices are discarded.
    public mutating func consume(
        _ request: Request, context: Context, options: [String], isActive: Bool
    ) -> String? {
        guard pending == request else { return nil }
        pending = nil
        guard isActive, request.context == context, options.contains(request.value) else {
            return nil
        }
        return request.value
    }
}
