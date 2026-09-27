import MonitorPresentation
import SwiftUI
import UIKit

/// Read actual native placement at the backdrop's existing sampling cadence.
/// Scrolling never publishes into the session or the SwiftUI observation graph.
@MainActor final class MultiviewStageGeometry {
    weak var controller: MultiviewStageController?

    func placement(_ index: Int) -> (frame: CGRect, clip: CGRect)? {
        controller?.placement(index)
    }
}

/// Keep every camera's SwiftUI root and native video host mounted while moving
/// its existing view between the stage and the secondary-camera scroll view.
struct MultiviewStageCanvas<Content: View>: UIViewControllerRepresentable {
    let ids: [UUID]
    let layout: MultiviewPresentationLayout
    let geometry: MultiviewStageGeometry
    @ViewBuilder var content: (Int) -> Content
    @Environment(\.self) private var environment

    func makeUIViewController(context: Context) -> MultiviewStageController {
        let controller = MultiviewStageController()
        geometry.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: MultiviewStageController, context: Context) {
        controller.update(
            ids: ids, layout: layout,
            roots: ids.indices.map { AnyView(content($0).environment(\.self, environment)) })
    }
}

@MainActor final class MultiviewStageController: UIViewController, UIScrollViewDelegate {
    private var hosts: [UUID: UIHostingController<AnyView>] = [:]
    private var ids: [UUID] = []
    private var geometry: MultiviewPresentationLayout?
    private let strip = UIScrollView()
    private let edgeMask = CAGradientLayer()
    private var previousEdges: [Bool] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        strip.backgroundColor = .clear
        strip.showsVerticalScrollIndicator = false
        strip.showsHorizontalScrollIndicator = false
        strip.contentInsetAdjustmentBehavior = .never
        strip.delegate = self
        strip.accessibilityIdentifier = "multiview.secondaryStrip"
        strip.accessibilityLabel = "Other cameras"
        view.addSubview(strip)
        strip.layer.mask = edgeMask
        edgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

    func update(ids: [UUID], layout: MultiviewPresentationLayout, roots: [AnyView]) {
        loadViewIfNeeded()
        let resetScroll =
            geometry?.secondaryViewport != layout.secondaryViewport
            || geometry?.secondaryIndices != layout.secondaryIndices
        self.ids = ids
        geometry = layout
        for (index, id) in ids.enumerated() {
            if let host = hosts[id] {
                host.rootView = roots[index]
            } else {
                let host = UIHostingController(rootView: roots[index])
                host.safeAreaRegions = []
                host.view.backgroundColor = .clear
                host.view.clipsToBounds = true
                addChild(host)
                view.addSubview(host.view)
                host.didMove(toParent: self)
                hosts[id] = host
            }
        }
        for id in hosts.keys.filter({ !ids.contains($0) }) {
            guard let host = hosts.removeValue(forKey: id) else { continue }
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        if resetScroll { strip.setContentOffset(.zero, animated: false) }
        placeHosts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeHosts()
    }

    private func placeHosts() {
        guard let geometry else { return }
        let viewport = geometry.secondaryViewport?.cgRect ?? .zero
        strip.isHidden = viewport.isEmpty
        strip.frame = viewport
        for (index, id) in ids.enumerated() {
            guard let host = hosts[id] else { continue }
            let secondary = geometry.secondaryIndices.contains(index)
            let parent: UIView = secondary ? strip : view
            if host.view.superview !== parent { parent.addSubview(host.view) }
            let frame = geometry.tiles[index].cgRect
            host.view.frame =
                secondary
                ? frame.offsetBy(dx: -viewport.minX, dy: -viewport.minY) : frame
        }
        let contentHeight: CGFloat = geometry.secondaryIndices.reduce(0) { height, index in
            max(height, CGFloat(geometry.tiles[index].maxY) - viewport.minY)
        }
        strip.contentSize = CGSize(width: viewport.width, height: contentHeight)
        let offset = max(0, min(strip.contentOffset.y, contentHeight - viewport.height))
        if strip.contentOffset.y != offset {
            strip.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }
        updateFades()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateFades() }

    private func updateFades() {
        let above = strip.contentOffset.y > 1
        let below = strip.contentOffset.y + strip.bounds.height < strip.contentSize.height - 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // UIScrollView moves its layer bounds while scrolling. Keep the alpha
        // mask in the visible viewport, fading the contents rather than painting
        // an opaque gradient over the picture or panel background.
        edgeMask.frame = strip.bounds
        let edge = min(0.5, 18 / max(1, strip.bounds.height))
        edgeMask.locations = [
            0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1,
        ]
        if previousEdges != [above, below] {
            edgeMask.colors = [
                (above ? UIColor.clear : .white).cgColor, UIColor.white.cgColor,
                UIColor.white.cgColor, (below ? UIColor.clear : .white).cgColor,
            ]
            previousEdges = [above, below]
        }
        CATransaction.commit()
    }

    func placement(_ index: Int) -> (frame: CGRect, clip: CGRect)? {
        guard ids.indices.contains(index), let host = hosts[ids[index]] else { return nil }
        let frame = host.view.convert(host.view.bounds, to: view)
        let clip = host.view.superview === strip ? frame.intersection(strip.frame) : frame
        return clip.isEmpty ? nil : (frame, clip)
    }
}
