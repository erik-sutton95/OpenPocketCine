import UIKit
import XCTest

@testable import OpenPocketCine

@MainActor
final class InterfaceOrientationObserverTests: XCTestCase {
    func testRepeatedStartOwnsOneSubscriptionAndStopIsIdempotent() {
        let center = TrackingOrientationNotificationCenter()
        let observer = InterfaceOrientationObserver(notificationCenter: center)
        observer.start()
        observer.start()
        XCTAssertEqual(center.activeSubscriptions, 1)
        XCTAssertEqual(center.registrations, 1)

        observer.stop()
        observer.stop()
        XCTAssertEqual(center.activeSubscriptions, 0)
        XCTAssertEqual(center.removals, 1)

        observer.start()
        XCTAssertEqual(center.activeSubscriptions, 1)
        XCTAssertEqual(center.registrations, 2)
        observer.stop()
    }

    func testReleasingAPageObserverRemovesItsNotificationSubscription() {
        let center = TrackingOrientationNotificationCenter()
        var observer: InterfaceOrientationObserver? = InterfaceOrientationObserver(
            notificationCenter: center)
        weak var released = observer
        observer?.start()
        XCTAssertEqual(center.activeSubscriptions, 1)
        observer = nil
        XCTAssertNil(released)
        XCTAssertEqual(center.activeSubscriptions, 0)
        XCTAssertEqual(center.removals, 1)
    }
}

/// Exercises the same NotificationCenter subscription seam as every page,
/// without depending on a physical rotation or a particular simulator scene.
private final class TrackingOrientationNotificationCenter: NotificationCenter, @unchecked Sendable {
    private var tokens: Set<ObjectIdentifier> = []
    private(set) var registrations = 0
    private(set) var removals = 0
    var activeSubscriptions: Int { tokens.count }

    override func addObserver(
        forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> any NSObjectProtocol {
        let token = super.addObserver(forName: name, object: obj, queue: queue, using: block)
        tokens.insert(ObjectIdentifier(token))
        registrations += 1
        return token
    }

    override func removeObserver(_ observer: Any) {
        if let token = observer as? any NSObjectProtocol,
            tokens.remove(ObjectIdentifier(token)) != nil
        {
            removals += 1
        }
        super.removeObserver(observer)
    }
}
