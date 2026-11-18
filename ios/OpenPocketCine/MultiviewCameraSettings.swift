import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineMulticam
import OpenPocketViewCore
import SwiftUI
import OpenCineMedia

extension MultiviewSession {
    /// The stage's rule, with what only Pocket knows (`admitsControls`): the tile's own
    /// datalink and no borrowed Live View.
    func controlsAvailable(for tile: Tile) -> Bool {
        guard let slot = tiles.firstIndex(where: { $0 === tile }) else { return false }
        return coordinator.controlsAvailable(slot: slot)
    }

    /// One editor at a time; changing tabs retires queued SETs before binding the next camera.
    @discardableResult
    func openCameraSettings(_ tile: Tile) -> AppModel? {
        guard let slot = tiles.firstIndex(where: { $0 === tile }) else { return nil }
        // The engine's editor lease names this tile's session and control epoch: a replaced
        // link or camera, a lost authority or the next editor retires it (plan 7.5). Opening it
        // closes every other editor first.
        let lease = coordinator.openEditorLease(slot: slot)
        guard let camera = tile.camera else { return nil }
        let editor = CameraSession(borrowing: tile.decoder, controlsOnly: true)
        let model = AppModel(session: editor)
        editor.updateMultiview(camera: camera, driver: tile.driver, status: tile.settings)
        // The capture drums edit through the shared control model; retiring unbinds it.
        model.control.bind(editor.control)
        model.frameSamples = tile.sampleBus
        tile.controlsModel = model
        tile.previewDemand = true
        editor.multiviewControlAdmission = { [weak self, weak tile, weak editor] in
            guard let self, let tile, let editor, let lease else { return false }
            return tile.controlsModel?.session === editor
                && coordinator.editorAdmits(lease, slot: slot)
                && controlsAvailable(for: tile)
        }
        return model
    }

    func closeCameraSettings() { coordinator.closeEditors() }
}

extension MultiviewSession.Tile {
    /// The settings popup's preview: the tile's own picture (color and Auto LUT), without scope or
    /// sample demand.
    var settingsPreviewEffects: MonitorFrameEffects {
        var result = effects
        result.inspectorSample = false
        return result
    }
}
