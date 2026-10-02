import OpenCineCore
import OpenPocketViewCore

extension CameraSession {
    /// The shell closes only its current common connection. The binding fences old closes before
    /// replacement and clears its owner before this existing native teardown can reenter it.
    func makeControlSessionBinding() -> DJIControlSessionBinding {
        DJIControlSessionBinding(
            port: self,
            onClose: { [weak self] _ in
                self?.disconnect()
            })
    }
}
