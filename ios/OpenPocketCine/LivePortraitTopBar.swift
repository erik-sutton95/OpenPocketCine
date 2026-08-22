import SwiftUI

/// OpenZCine portrait info bar: full-width 44 pt glass, centered storage,
/// leading timecode, trailing camera-only inline battery.
struct LivePortraitTopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if model.chromeSectionMounts(.storage) {
                LivePortraitStorageReadout()
            }
            HStack(spacing: 10) {
                if model.chromeSectionMounts(.timecode) {
                    LivePortraitTimecode()
                }
                Spacer(minLength: 8)
                if model.chromeSectionMounts(.batteries) {
                    LivePortraitCameraBattery()
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiveDesign.glass)
        .environment(\.colorScheme, .dark)
    }
}

private struct LivePortraitTimecode: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let clock = model.session.status.timecodeClock
        Text(clock.isEmpty ? "00:00:00" : clock)
            .font(.system(size: 15, weight: .regular, design: .monospaced))
            .foregroundStyle(LiveDesign.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct LivePortraitStorageReadout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LiveDesign.text)
            .lineLimit(1)
    }

    private var label: String {
        let s = model.session.status
        let free = s.storageFreeMb > 0 ? s.storageFreeMb : s.sdFreeMb
        let total = s.storageTotalMb > 0 ? s.storageTotalMb : s.sdTotalMb
        if total > 0 {
            let gb = max(0, free) / 1024
            let pct = Int((Double(max(0, free)) / Double(total) * 100).rounded())
            return "\(gb) GB · \(pct)%"
        }
        if s.recordRemainingSec > 0 { return "\(s.recordRemainingSec / 60) Min" }
        return "—"
    }
}

private struct LivePortraitCameraBattery: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let percent = model.session.status.batteryPercent
        HStack(spacing: 4) {
            OpcIcon.camera
                .frame(width: 11, height: 11)
            Text(percent > 0 ? "\(percent)%" : "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(LiveDesign.text)
    }
}
