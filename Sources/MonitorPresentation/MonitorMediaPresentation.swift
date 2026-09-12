import Foundation

/// Library data prepared by the camera adapter. It carries no URLs, handles,
/// transport state or decoder objects into the reusable catalog screen.
public struct MonitorMediaItem: Identifiable, Equatable, Sendable {
    public enum Availability: String, Equatable, Sendable {
        case camera, proxy, original
    }

    public let id: String
    public let filename: String
    public let metadata: String
    public let format: String
    public let color: String
    public let duration: String
    public let date: String
    public let availability: Availability
    public let progress: Double?
    public let favorite: Bool
    public let photo: Bool
    public let permissions: MonitorMediaPermissions

    public init(
        id: String, filename: String, metadata: String, format: String = "",
        color: String = "", duration: String = "", date: String = "",
        availability: Availability, progress: Double? = nil,
        favorite: Bool, photo: Bool, permissions: MonitorMediaPermissions = []
    ) {
        self.id = id
        self.filename = filename
        self.metadata = metadata
        self.format = format
        self.color = color
        self.duration = duration
        self.date = date
        self.availability = availability
        self.progress = progress
        self.favorite = favorite
        self.photo = photo
        self.permissions = permissions
    }

    public var stateLabel: String {
        if progress != nil { return "CACHING" }
        switch availability {
        case .camera: return "ON CAMERA"
        case .proxy: return "PROXY"
        case .original: return "ON PHONE"
        }
    }
}

public struct MonitorMediaCategory: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let count: Int
    public init(id: String, title: String, count: Int) {
        self.id = id
        self.title = title
        self.count = count
    }
}

public enum MonitorMediaLayout: String, Equatable, Sendable { case grid, list }
public enum MonitorThumbnailSize: String, CaseIterable, Equatable, Sendable {
    case small, medium, large

    public func columns(tablet: Bool) -> Int {
        switch self {
        case .small: return tablet ? 5 : 3
        case .medium: return tablet ? 4 : 2
        case .large: return tablet ? 2 : 1
        }
    }
}

/// UI intents. Camera-specific operations are implemented by the host adapter.
public enum MonitorMediaAction: Equatable, Sendable {
    case back, refresh, cycleSort
    case category(String)
    case open(String)
    case select(String)
    case favorite(String)
    case layout(MonitorMediaLayout)
    case thumbnailSize(MonitorThumbnailSize)
    case selectAll, clearSelection, shareSelection, cacheSelection, favoriteSelection,
        deleteSelection
}

/// Per-clip operations currently offered by the adapter. Unsupported controls
/// cannot become enabled merely because a future backend reuses the screen.
public struct MonitorMediaPermissions: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let share = Self(rawValue: 1 << 0)
    public static let cache = Self(rawValue: 1 << 1)
    public static let favorite = Self(rawValue: 1 << 2)
    public static let delete = Self(rawValue: 1 << 3)
}
