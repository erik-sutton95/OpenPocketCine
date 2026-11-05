import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
#if targetEnvironment(macCatalyst)
    import OpenCineVirtualCamera
#endif
import SwiftUI
import UIKit

@main
struct OpenPocketCineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
            MultiviewUIReview.prepareIfRequested()
            AppDiagnostics.verification.prepareIfRequested()
        #endif
        AppDiagnostics.reporting.noteFeedUpscaler(FeedUpscaleSwitch.shared.upscaler.rawValue)
        AppDiagnostics.reporting.install()
        #if DEBUG
            AppDiagnostics.verification.runIfRequested()
        #endif
        MonitorTheme.prepareResources()
        FeedStressAutomation.installIfRequested(
            host: { AppModelDiagnosticsAnchor.model },
            onInjectionActivated: { AppDiagnostics.reporting.noteCurrentTestSource(.faultInjection) })
    }

    var body: some Scene {
        WindowGroup {
            root
                .observeMonitorWindowGeometry()
                // The monitor's lock button also holds the screen rotation.
                .monitorRotationLock(appDelegate.monitorRotation)
                // iPad ignores Info.plist `UIStatusBarHidden` after launch unless
                // the hosting controller prefers it hidden. `~ipad` covers launch.
                .statusBarHidden(true)
                #if targetEnvironment(macCatalyst)
                    .task { DesktopModuleHost.current?.start() }
                #endif
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
            if ReliabilityReportingVerification.mode != nil {
                Text("Reliability verification")
            } else if MultiviewUIReview.isActive {
                MultiviewUIReviewRoot()
            } else {
                AppRoot()
            }
        #else
            AppRoot()
        #endif
    }
}

/// Answers the app's supported orientations from the monitor's rotation hold, so the lock button
/// keeps an inverted rig's screen from turning when the phone is levelled.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let monitorRotation = MonitorRotationLock()

    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        monitorRotation.supportedOrientations
    }
}
