import OpenPocketViewCore
import SwiftUI

/// Presentation preferences only. Meter values and peak hold remain the camera's.
extension AudioAssist {
    enum Orientation: String, Codable, CaseIterable, Sendable {
        case vertical = "Vertical"
        case horizontal = "Horizontal"
    }

    struct StoredCenter: Codable, Equatable {
        var x: Double
        var y: Double

        init(_ center: CGPoint, in bounds: CGRect) {
            x = (center.x - bounds.minX) / max(1, bounds.width)
            y = (center.y - bounds.minY) / max(1, bounds.height)
        }

        func point(in bounds: CGRect) -> CGPoint {
            CGPoint(
                x: bounds.minX + (x.isFinite ? x : 0.5) * bounds.width,
                y: bounds.minY + (y.isFinite ? y : 0.5) * bounds.height)
        }
    }

    struct Options: Codable, Equatable {
        var orientation: Orientation = .vertical
        var showsDB = false
        var landscapeCenter: StoredCenter?
        var portraitCenter: StoredCenter?
    }

    static func panelSize(orientation: Orientation) -> CGSize {
        orientation == .vertical
            ? panelSize : CGSize(width: panelSize.height, height: panelSize.width)
    }

    static func levelFraction(_ db: Double) -> Double {
        guard db.isFinite else { return 0 }
        return min(1, max(0, (db - AudioMeterBallistics.floorDB) / -AudioMeterBallistics.floorDB))
    }

    static func dbText(_ db: Double) -> String {
        guard db.isFinite, db > AudioMeterBallistics.floorDB + 0.5 else { return "−∞" }
        return String(format: "%.0f", min(0, db))
    }

    static func center(
        stored: StoredCenter?, size: CGSize, canvas: CGRect, movement: CGRect
    ) -> CGPoint {
        let fallback = CGPoint(x: movement.minX + size.width / 2, y: canvas.midY)
        let point = stored?.point(in: canvas) ?? fallback
        let minX = movement.minX + size.width / 2
        let minY = movement.minY + size.height / 2
        return CGPoint(
            x: min(max(minX, point.x), max(minX, movement.maxX - size.width / 2)),
            y: min(max(minY, point.y), max(minY, movement.maxY - size.height / 2)))
    }

    @MainActor static var store: AudioAssistStore { AudioAssistStore.shared }
}

@MainActor
@Observable
final class AudioAssistStore {
    static let shared = AudioAssistStore()
    private let defaults: UserDefaults
    private let key: String
    var options: AudioAssist.Options

    init(defaults: UserDefaults = .standard, key: String = "OpenPocketCine.Assist.audio.v1") {
        self.defaults = defaults
        self.key = key
        options =
            defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(AudioAssist.Options.self, from: $0) }
            ?? AudioAssist.Options()
    }

    func storedCenter(in bounds: CGRect) -> AudioAssist.StoredCenter? {
        ScopeCanvasSlot.pick(options.landscapeCenter, options.portraitCenter, in: bounds)
    }

    func setCenter(_ center: CGPoint, in bounds: CGRect) {
        let stored = AudioAssist.StoredCenter(center, in: bounds)
        if bounds.height > bounds.width {
            options.portraitCenter = stored
        } else {
            options.landscapeCenter = stored
        }
        persist()
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: key)
    }
}
