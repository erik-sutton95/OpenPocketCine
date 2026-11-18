import MonitorPresentation
import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import MonitorUI
import OpenCineCameraControls
import OpenCineHostedAccessibility
import SwiftUI
import UIKit
import XCTest

@testable import OpenPocketCine

/// A2-26: the Licenses and NOTICE pages are the repository files themselves, rendered by the
/// actual shared legal screen. SIMULATED host window and app model; no camera and no network.
@MainActor final class SettingsLegalSupportTests: XCTestCase {
    private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func repositoryText(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testBundledLegalFilesAreTheRepositoryFilesByteForByte() throws {
        for (copy, canonical) in [("NOTICE", "NOTICE"), ("LICENSE", "LICENSE"),
            ("THIRD-PARTY-NOTICES", "THIRD-PARTY-NOTICES.md")] {
            let bundled = try XCTUnwrap(Bundle.main.url(forResource: copy, withExtension: "txt", subdirectory: "Legal"),
                "Legal/\(copy).txt ships in the app bundle")
            XCTAssertEqual(try Data(contentsOf: bundled), try Data(contentsOf: repository.appending(path: canonical)),
                "Legal/\(copy).txt is the repository file, staged at build time")
        }
    }

    func testRenderedNoticeAndLicensesAreTheBundledFilesAndCloseReopens() async throws {
        let licenses = try [repositoryText("LICENSE"), repositoryText("THIRD-PARTY-NOTICES.md"),
            XCTUnwrap(MonitorPlatformLegalNotices.text)].joined(separator: "\n\n")
        XCTAssertEqual(MonitorLegalDocuments.app.notice, .text(try repositoryText("NOTICE")))
        XCTAssertEqual(MonitorLegalDocuments.app.licenses, .text(licenses))
        for (page, expected) in [(MonitorLegalPage.notice, try repositoryText("NOTICE")), (.licenses, licenses),
            (.notice, try repositoryText("NOTICE"))] {
            var closed = 0
            let fixture = try Fixture(LegalDocumentView(kind: page, onClose: { closed += 1 }).environment(AppModel()))
            defer { fixture.close() }
            let body = try await fixture.element("legal.document.\(page.rawValue)")
            XCTAssertEqual(body.accessibilityLabel, expected)
            let close = try await fixture.element("legal.document.close")
            XCTAssertTrue(close.accessibilityActivate())
            XCTAssertEqual(closed, 1)
        }
    }

    /// A2-22/A2-26: the System tab renders the shared support rows in the shared order, and its
    /// NOTICE row opens the shared legal screen with the repository file.
    func testSettingsSystemTabUsesTheSharedSupportRowsAndLegalScreen() async throws {
        let model = AppModel()
        model.operatorSession.settingsTab = .system
        let fixture = try Fixture(SettingsRootView(onClose: {}).environment(model))
        defer { fixture.close() }
        var positions: [Int] = []
        for label in ["Share Diagnostics", "Delete saved feed reports", "Open Source Code", "Open Privacy Policy",
            "Open Terms of Use", "Open Licenses", "Open NOTICE"] {
            positions.append(try await fixture.position(label: label))
        }
        XCTAssertEqual(positions, positions.sorted(), "Support rows keep the shared order")
        let openNotice = try await fixture.element(label: "Open NOTICE")
        XCTAssertTrue(openNotice.accessibilityActivate())
        let body = try await fixture.element("legal.document.notice")
        XCTAssertEqual(body.accessibilityLabel, try repositoryText("NOTICE"))
        let closeNotice = try await fixture.element("legal.document.close")
        XCTAssertTrue(closeNotice.accessibilityActivate())
        try await fixture.gone("legal.document.notice")
        let openLicenses = try await fixture.element(label: "Open Licenses")
        XCTAssertTrue(openLicenses.accessibilityActivate())
        _ = try await fixture.element("legal.document.licenses")
    }

    /// A2-23: Settings signs in to this app's Frame.io account and, like its support links, asks
    /// before leaving the camera's Wi-Fi through the app's one internet hop (Core
    /// MonitorSettingsAccountHopTests and MonitorBrowserInternetHandoffTests cover the hop itself).
    func testSettingsAccountAndSupportUseTheAppAccountAndItsInternetHop() {
        let model = AppModel()
        let account = model.settingsAccountActions
        XCTAssertEqual(account.identity, AnyHashable(ObjectIdentifier(model.frameio)))
        XCTAssertEqual(account.requiresInternetConsent, model.isOnCameraAccessPoint)
        let support = model.settingsSupportActions
        XCTAssertEqual(support.identity, AnyHashable(ObjectIdentifier(model)))
        XCTAssertEqual(support.requiresInternetConsent, model.isOnCameraAccessPoint)
        XCTAssertFalse(model.browserHandoff.isHolding)
    }

    /// A2-35/A2-36: Settings composes the typed domains: every tab, the HDR panel and originals
    /// caching present as values, the common Controls rows and the automatic-reports row.
    func testSettingsRenderEveryTypedDomain() async throws {
        let model = AppModel()
        var rows: [MonitorSettingsTab: [String]] = [:]
        for tab in MonitorSettingsTab.allCases {
            model.operatorSession.settingsTab = tab
            let fixture = try Fixture(SettingsRootView(onClose: {}).environment(model))
            let rendered = try await fixture.settingsTitles()
            fixture.close()
            XCTAssertEqual(rendered.tabs, MonitorSettingsTab.allCases.map { "monitor.settings.tab.\($0.id)" },
                "Every domain is present, in the shared order")
            rows[tab] = rendered.rows
        }
        XCTAssertTrue(["Record confirmation", "Haptics", "Keep screen awake"].allSatisfy { rows[.controls]?.contains($0) == true })
        // The camera presets card leads the Controls tab.
        XCTAssertEqual(rows[.controls]?.first, CameraSettingsPresetCopy.title, "\(rows[.controls] ?? [])")
        XCTAssertTrue(rows[.display]?.contains("HDR display") == true, "\(rows[.display] ?? [])")
        XCTAssertTrue(rows[.storage]?.contains("Full Resolution Caching") == true, "\(rows[.storage] ?? [])")
        XCTAssertTrue(rows[.system]?.contains("Automatic error reports") == true, "\(rows[.system] ?? [])")
        // A2-78: the one Processing card, before Your cameras, with the shared Feed Upscaler.
        let link = rows[.link] ?? []
        let processing = try XCTUnwrap(link.firstIndex(of: "Processing"), "\(link)")
        XCTAssertLessThan(processing, try XCTUnwrap(link.firstIndex(of: "Your cameras"), "\(link)"))
        XCTAssertEqual(link.firstIndex(of: "Feed Upscaler"), processing + 1, "\(link)")
    }

    /// A2-24: Report a problem in Settings opens the app root's report, so a draft outlives the
    /// camera session ending, which closes the Settings cover. Settings presents no sheet itself.
    func testSettingsReportOpensTheRootReportThatOutlivesTheSession() async throws {
        let model = AppModel()
        model.operatorSession.settingsTab = .system
        model.shell.present(ConnectedCamera(saved: OpenCineCore.SavedCamera(
            id: "simulated-report", integration: DJICameraSessionAdapter.integration,
            advertisedName: "SIMULATED report", model: "SIMULATED"), session: model.session.control))
        model.shell.open(.settings)
        let fixture = try Fixture(SettingsRootView(onClose: {}).environment(model))
        defer { fixture.close() }
        let open = try await fixture.element("support.report.open")
        XCTAssertTrue(open.accessibilityActivate())
        XCTAssertTrue(model.isProblemReportPresented)
        XCTAssertNil(fixture.host.presentedViewController, "Settings presents no report sheet of its own")
        model.shell.close()
        XCTAssertNil(model.shell.cover, "Ending the session closes the Settings cover")
        XCTAssertTrue(model.isProblemReportPresented, "The root report survives the session ending")
    }

    /// In-app privacy matches the website (2026-10-16): it reads the shared reliability paragraph,
    /// which names the random install identifier deleted on opt-out.
    func testPrivacyReadsTheSharedReliabilityParagraph() throws {
        guard case .text(let privacy) = MonitorLegalDocuments.app.privacy else { return XCTFail("privacy is bundled text") }
        XCTAssertTrue(privacy.contains(MonitorSettingsCopy.reliabilityReportsPrivacy))
        XCTAssertTrue(privacy.contains("install identifier"))
    }

    func testAMissingBundledPageSaysSoInsteadOfShowingAnEmptyPage() async throws {
        let documents = MonitorLegalDocuments(wordmark: "SIMULATED", privacy: .unavailable,
            terms: .unavailable, licenses: .unavailable, notice: .unavailable)
        let fixture = try Fixture(MonitorLegalDocumentScreen(documents: documents, page: .notice, onClose: {}))
        defer { fixture.close() }
        let body = try await fixture.element("legal.document.notice")
        XCTAssertEqual(body.accessibilityLabel, MonitorLegalDocuments.unavailableText)
    }
}

@MainActor private struct Fixture {
    let window: UIWindow
    let host: UIViewController
    let previous: UIWindow?

    init(_ view: some View) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previous = scene.keyWindow
        host = UIHostingController(rootView: view)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 420, height: 900)
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    func element(_ identifier: String) async throws -> NSObject {
        try await first(identifier) { HostedAccessibility.identifier($0) == identifier }
    }

    func element(label: String) async throws -> NSObject {
        try await first(label) { $0.accessibilityLabel == label }
    }

    /// The preorder position of the first element with `label`, for row order.
    func position(label: String) async throws -> Int {
        _ = try await element(label: label)
        return try XCTUnwrap(HostedAccessibility.elements(in: host.view).firstIndex { $0.accessibilityLabel == label })
    }

    func gone(_ identifier: String) async throws {
        for _ in 0..<200 {
            host.view.layoutIfNeeded()
            if !HostedAccessibility.elements(in: host.view).contains(where: {
                HostedAccessibility.identifier($0) == identifier
            }) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MissingElement(identifier: "still showing \(identifier)")
    }

    private func first(_ name: String, where matches: (NSObject) -> Bool) async throws -> NSObject {
        for _ in 0..<200 {
            host.view.layoutIfNeeded()
            if let found = HostedAccessibility.elements(in: host.view).first(where: matches) { return found }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MissingElement(identifier: name)
    }

    struct MissingElement: Error { let identifier: String }

    /// The settings tab identifiers and the card and row titles on screen, in order, once the
    /// page stops changing.
    func settingsTitles() async throws -> (tabs: [String], rows: [String]) {
        var tabs: [String] = [], rows: [String] = [], settled = 0
        for _ in 0..<200 {
            host.view.layoutIfNeeded()
            var nextTabs: [String] = [], nextRows: [String] = []
            for element in HostedAccessibility.elements(in: host.view) {
                guard let id = HostedAccessibility.identifier(element) else { continue }
                if id.hasPrefix("monitor.settings.tab."), !nextTabs.contains(id) { nextTabs.append(id) }
                if id == "monitor.settings.row.title" || id == "monitor.settings.card.title" {
                    nextRows.append(element.accessibilityLabel ?? "")
                }
            }
            settled = !nextTabs.isEmpty && nextTabs == tabs && nextRows == rows ? settled + 1 : 0
            tabs = nextTabs; rows = nextRows
            if settled >= 3 { return (tabs, rows) }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MissingElement(identifier: "settled settings page")
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        if let previous, !previous.isHidden { previous.makeKeyAndVisible() }
    }
}
