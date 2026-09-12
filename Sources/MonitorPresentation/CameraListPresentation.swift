import Foundation

/// Camera identities and display values supplied by an adapter. No protocol bytes or
/// camera-brand decisions belong in the native camera picker.
public struct CameraListItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var badge: String
    public var status: String
    public var actionTitle: String
    public var isPrimary: Bool
    public var isBusy: Bool
    public var isAvailable: Bool
    public var signalBars: Int?
    public var details: [CameraPresentationDetail]

    public init(
        id: String, name: String, subtitle: String, badge: String = "",
        status: String, actionTitle: String, isPrimary: Bool = false,
        isBusy: Bool = false, isAvailable: Bool = true, signalBars: Int? = nil,
        details: [CameraPresentationDetail] = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.badge = badge
        self.status = status
        self.actionTitle = actionTitle
        self.isPrimary = isPrimary
        self.isBusy = isBusy
        self.isAvailable = isAvailable
        self.signalBars = signalBars.map { min(4, max(0, $0)) }
        self.details = details
    }
}

public struct CameraPresentationDetail: Equatable, Identifiable, Sendable {
    public var title: String
    public var value: String
    public var id: String { title }

    public init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
}

/// This describes presentation only. A backend remains the sole owner of connection
/// progress; the UI cannot advance a pairing stage by marking it complete.
public struct CameraPairingStep: Equatable, Identifiable, Sendable {
    public var title: String
    public var subtitle: String
    public var id: String { title }

    public init(_ title: String, _ subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct CameraPairingInstruction: Equatable, Identifiable, Sendable {
    public enum Icon: Sendable { case camera, phone }
    public var title: String
    public var icon: Icon
    public var lines: [String]
    public var id: String { title }

    public init(title: String, icon: Icon, lines: [String]) {
        self.title = title
        self.icon = icon
        self.lines = lines
    }
}

public struct CameraPairingCheck: Equatable, Identifiable, Sendable {
    public enum State: Sendable { case complete, active, waiting }
    public var title: String
    public var subtitle: String
    public var state: State
    public var stateLabel: String
    public var id: String { title }

    public init(title: String, subtitle: String, state: State, stateLabel: String) {
        self.title = title
        self.subtitle = subtitle
        self.state = state
        self.stateLabel = stateLabel
    }
}

public struct CameraPairingPresentation: Equatable, Sendable {
    public var steps: [CameraPairingStep]
    public var currentStep: Int
    public var title: String
    public var body: String
    public var target: String
    public var hint: String
    public var progress: String?
    public var error: String?
    public var devices: [CameraListItem]
    public var instructions: [CameraPairingInstruction]
    public var checks: [CameraPairingCheck]
    public var summary: [CameraPresentationDetail]
    public var emptyTitle: String?
    public var primaryAction: String?
    public var primaryActionEnabled: Bool
    public var backAction: String?

    public init(
        steps: [CameraPairingStep], currentStep: Int, title: String, body: String,
        target: String, hint: String, progress: String? = nil, error: String? = nil,
        devices: [CameraListItem] = [], instructions: [CameraPairingInstruction] = [],
        checks: [CameraPairingCheck] = [], summary: [CameraPresentationDetail] = [],
        emptyTitle: String? = nil, primaryAction: String? = nil,
        primaryActionEnabled: Bool = false, backAction: String? = nil
    ) {
        self.steps = steps
        self.currentStep = min(max(0, currentStep), max(0, steps.count - 1))
        self.title = title
        self.body = body
        self.target = target
        self.hint = hint
        self.progress = progress
        self.error = error
        self.devices = devices
        self.instructions = instructions
        self.checks = checks
        self.summary = summary
        self.emptyTitle = emptyTitle
        self.primaryAction = primaryAction
        self.primaryActionEnabled = primaryActionEnabled
        self.backAction = backAction
    }
}
