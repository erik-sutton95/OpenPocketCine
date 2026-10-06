import OpenPocketViewCore

extension LUTSelection {
    static func djiCatalog(isPhotoLive: Bool) -> [LUTSelection] {
        isPhotoLive ? [.officialAuto] : djiCases
    }
}
