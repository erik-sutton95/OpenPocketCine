import Foundation
import OpenCineAppKit
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore

/// Rendered legacy row IDs route only to the actual captured content in this gallery lifetime.
@MainActor struct PocketMediaLibraryPresentation {
    let owner: MonitorMediaLibraryModel<MediaFile>
    let token: MonitorMediaLibraryActionToken
    private let rendered: [String: MediaAssetID]

    init(owner: MonitorMediaLibraryModel<MediaFile>, records: [MonitorMediaRecord<MediaFile>]? = nil) {
        self.owner = owner; token = owner.actionToken
        rendered = Dictionary((records ?? owner.records).map { ($0.payload.id, $0.asset.id) },
            uniquingKeysWith: { _, latest in latest })
    }
    var isCurrent: Bool { owner.isCurrent(token) }
    var selectedIDs: Set<String> {
        Set(owner.records.filter { owner.selectedIDs.contains($0.asset.id) }.map { $0.payload.id })
    }
    func file(_ id: String) -> MediaFile? {
        guard isCurrent, let asset = rendered[id], let current = owner.record(asset) else { return nil }
        var file = current.payload; file.isStarred = current.favorite; return file
    }
    @discardableResult func select(_ ids: Set<String>, selecting: Bool = true) -> Bool {
        guard isCurrent else { return false }
        var mapped: Set<MediaAssetID> = []
        for id in ids {
            guard let asset = rendered[id], owner.record(asset) != nil else { return false }
            mapped.insert(asset)
        }
        owner.select(mapped, selecting: selecting)
        return isCurrent
    }
}
