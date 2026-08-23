import SwiftUI
import UIKit

/// OpenPocketCine brand palette — DJI Sky Blue on Black.
enum BrandColors {
    static let background = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    static let backgroundDeep = Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255)
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    static let ink = Color.white
    static let muted = Color(red: 160 / 255, green: 165 / 255, blue: 165 / 255)
    static let accent = Color(red: 0, green: 163 / 255, blue: 230 / 255)
    static let accentSoft = Color(red: 0, green: 163 / 255, blue: 230 / 255).opacity(0.18)
}

/// App mark from the AppLogo raster; falls back to a drawn monogram.
struct OPCMonogramMark: View {
    var size: CGFloat = 72

    var body: some View {
        let cornerRadius = size * 0.22
        Group {
            if let logo = UIImage(named: "AppLogo") ?? UIImage(named: "AppLogo.png") {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BrandColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                BrandColors.accent.opacity(0.55), lineWidth: max(1, size * 0.018))
                    )
                    .overlay {
                        Text("OPC")
                            .font(LiveType.display(size * 0.34, weight: .heavy))
                            .kerning(size * 0.02)
                            .foregroundStyle(BrandColors.accent)
                    }
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.04)
        .accessibilityLabel("OpenPocketCine")
    }
}

struct OpenPocketCineWordmark: View {
    var fontSize: CGFloat = 34
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.18) {
            Text("OpenPocketCine")
                .font(LiveType.ui(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColors.ink)
            if let subtitle {
                Text(subtitle)
                    .font(LiveType.ui(size: fontSize * 0.38, weight: .medium, design: .rounded))
                    .foregroundStyle(BrandColors.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum LaunchSplashTiming {
    static let visibleDuration: Duration = .milliseconds(2_250)
    static let fadeOutDuration: TimeInterval = 0.35
}

struct BrandBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255),
                    Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255),
                    Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 45 / 255, green: 111 / 255, blue: 160 / 255).opacity(0.28),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct LaunchSplashContent: View {
    var compact: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            let logoSize = min(proxy.size.width * (landscape ? 0.16 : 0.28), compact ? 72 : 96)

            ZStack {
                BrandBackdrop()

                if landscape {
                    HStack(spacing: max(32, proxy.size.width * 0.06)) {
                        OPCMonogramMark(size: logoSize)
                        OpenPocketCineWordmark(fontSize: compact ? 28 : 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, max(32, proxy.size.width * 0.08))
                } else {
                    VStack(spacing: 24) {
                        OPCMonogramMark(size: logoSize)
                        OpenPocketCineWordmark(fontSize: 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct LaunchSplashOverlay: View {
    @Binding var isVisible: Bool

    var body: some View {
        LaunchSplashContent()
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: LaunchSplashTiming.fadeOutDuration), value: isVisible)
            .allowsHitTesting(isVisible)
    }
}
