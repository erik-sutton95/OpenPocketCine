/// Presentation of the camera's exposure meter. Never derived from preview pixels
/// or from the operator's configured exposure compensation.
public struct ExposureMeterReading: Equatable, Sendable {
    private let cameraValue: EvComp?

    public init(cameraValue: EvComp?) {
        self.cameraValue = cameraValue
    }

    public var stops: Double? { cameraValue.map { Double($0.thirds) / 3 } }
    public var needleFraction: Double? { cameraValue.map { Double($0.thirds + 9) / 18 } }
    public var label: String { cameraValue?.label ?? "—" }

    public var accessibilityValue: String {
        cameraValue == nil ? "Unavailable, waiting for camera EV" : "Camera exposure \(label) EV"
    }
}
