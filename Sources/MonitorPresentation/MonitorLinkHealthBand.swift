/// Presentation bands from the Settings link-health scale. The caller supplies
/// the existing signal measurement; this does not score or monitor the link.
public enum MonitorLinkHealthBand: Equatable, Sendable {
    case poor, watch, stable

    public init(score: Int) {
        self = score >= 80 ? .stable : score >= 50 ? .watch : .poor
    }

    public init(bars: Int) {
        self.init(score: min(4, max(0, bars)) * 25)
    }
}
