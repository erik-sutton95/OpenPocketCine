import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import OpenCineAppKit
import OpenCineApple
import OpenCineMedia
import SwiftUI
import UIKit

// MARK: - Photo viewer

/// Source addresses and bounded UIKit decoding; common UI owns the complete photo page.
struct MediaPhotoViewer: View {
    let opening: MonitorMediaGalleryOpen<MediaFile>
    let library: MonitorMediaLibraryModel<MediaFile>
    let session: CameraSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var delivery: MediaFile?

    var body: some View {
        let captured = session
        let origin = model.shell.monitor?.id
        MonitorOperatorPhotoScreen(library: library, record: opening.record, admission: opening.admission,
            assist: model.assist, loaders: loaders(captured),
            operations: operations(captured),
            haptics: .app, coverPresented: delivery != nil, sourceCurrent: { [weak model, weak captured] in
                guard let model, let captured else { return false }
                return model.session === captured && captured.mediaLibrary === library
                    && model.shell.monitor?.id == origin
            }, close: { dismiss() }, share: { request in
                guard request.isCurrent() else { return }
                delivery = request.record.payload
            })
        .overlay {
            if let delivery {
                MediaDeliveryPopupOverlay(files: [delivery]) { self.delivery = nil }
            }
        }
        .overlay { MonitorOperatorDeliveryChrome(model: model.delivery.lifetime, scope: .surface, remoteDisplayName: "Frame.io") }
        .onDisappear { delivery = nil }
        .onChange(of: library.lifetimeToken) { _, _ in delivery = nil }
    }

    private func operations(_ session: CameraSession) -> MonitorMediaGalleryOperations<MediaFile> {
        if session.canReachCameraMedia {
            return .init(delete: { record in await session.deleteMedia(record.payload) },
                favorite: { record in session.toggleFavorite(record.payload) })
        }
        return .init(favorite: { record in session.toggleFavorite(record.payload) })
    }

    private func loaders(_ session: CameraSession) -> MonitorMediaPictureLoaders<MediaFile, UIImage> {
        .init(preview: { request in
            guard request.isCurrent(), let url = session.thumbnailURL(for: request.record.payload),
                let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }, cached: { request in
            let file = request.record.payload
            guard request.isCurrent(), session.isDownloaded(file), let url = session.localURL(for: file) else { return nil }
            return await MediaCellImageLoader.shared.downsampled(at: url, maxPixelSize: 4096)
        }, source: { request in
            guard request.isCurrent(), session.canReachCameraMedia,
                let bytes = await session.originalImageBytes(for: request.record.payload, ifCurrent: request.isCurrent) else { return nil }
            return await MediaCellImageLoader.shared.downsampled(data: bytes, maxPixelSize: 4096)
        })
    }
}

// MARK: - Player

struct MediaPlayerView: View {
    let opening: MonitorMediaGalleryOpen<MediaFile>
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var source = PocketPlaybackPresentationSource()
    @State private var owner: MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>?
    @State private var sourceAdmission: MonitorPlaybackAdmission?
    @State private var pictureGeometry: MonitorPlaybackPictureGeometry?
    @State private var deliveryFiles: [MediaFile]?
    init(opening: MonitorMediaGalleryOpen<MediaFile>) { self.opening = opening }

    var body: some View {
        Group {
            if let owner {
                player(owner, initial: opening)
                    .overlay {
                        if let deliveryFiles {
                            MediaDeliveryPopupOverlay(files: deliveryFiles) {
                                self.deliveryFiles = nil
                            }.zIndex(5)
                        }
                    }
                    .overlay { MonitorOperatorDeliveryChrome(model: model.delivery.lifetime, scope: .surface, remoteDisplayName: "Frame.io") }
            } else { MonitorOperatorMediaUnavailable(close: { dismiss() }) }
        }.onAppear {
            guard owner == nil else { return }
            let captured = model.session, origin = model.shell.monitor?.id
            sourceAdmission = .init { [weak model, weak captured] in
                guard let model, let captured else { return false }
                return model.session === captured && model.shell.monitor?.id == origin
            }
            owner = source.makeOwner(model: model)
        }
    }
    private func player(_ owner: MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>,
        initial: MonitorMediaGalleryOpen<MediaFile>) -> some View {
        @Bindable var model = model
        return MonitorOperatorPlaybackScreen(model: owner, initial: initial,
            assist: model.assist, stores: .app, looks: .app, palette: LiveDesign.self,
            haptics: .app, usage: $model.assistToolUsage,
            cacheOriginal: OperatorPrefs.cacheFullResolution,
            deliveryPresented: deliveryFiles != nil || model.delivery.isActive,
            operations: source.operations(model: model, owner: owner),
            source: { source.values(record: $0, model: model, owner: owner) },
            nativeAssists: { playback in
                guard playback.native === source.native else { return nil }
                return source.assists
            }, readScopes: { model.monitorSamples.displayBundle }, configureDisplay: scopeDisplay,
            sourceCurrent: { sourceAdmission?.isCurrent() == true },
            close: { dismiss() }, share: { record in
                deliveryFiles = [record.payload]
            }, onGeometry: { geometry in
                guard geometry.item == owner.playback?.token else { return }
                pictureGeometry = geometry
            }, picture: { playback, effects in
                nativePicture(owner, playback: playback, effects: effects)
            }, preview: { AssistInspectorPreview(tool: $0) },
            lookMenu: { LUTAssist.longPressMenu(assist: model.assist) })

            .monitorVideoBackdrop(renderer: model.playbackBackdrop,
                configuration: backdropConfiguration(owner),
                enabled: owner.playerVisible && owner.playback?.ready == true, surroundRGB: 0x000000
            ) { size in
                guard let playback = owner.playback, let native = source.native else { return [] }
                let token = playback.token, samples = model.frameSamples
                let epoch = samples.inspectorSourceEpoch
                guard owner.isCurrent(token), let buffer = native.feed.backdropSource() else { return [] }
                let dimensions = displaySize(playback)
                let rect = DesqueezeAssist.presentationRect(sourceSize: dimensions,
                    in: CGRect(origin: .zero, size: size), effects: model.assist.playbackEffects)
                var effects = model.assist.playbackEffects
                effects.clipByte = model.frameSamples.exposureCeiling.clipByte(transfer: effects.transfer)
                return [MonitorVideoBackdropSource(buffer: buffer, effects: effects,
                    frame: MonitorVideoBackdropSource.displayedFrame(
                        sourceAspect: dimensions.width / max(1, dimensions.height), effects: effects,
                        in: rect, zoom: pictureGeometry?.zoom.scale ?? 1,
                        offset: pictureGeometry?.zoom.offset ?? .zero), clip: rect, identity: .playback(item: token, epoch: epoch),
                    admission: { [weak owner, weak playback, weak native, weak source, weak samples] in
                        guard let owner, let playback, let native, let source, let samples else { return false }
                        return owner.isCurrent(token) && playback.token == token && source.native === native
                            && samples.inspectorSourceEpoch == epoch
                    })]
            }
    }
    @ViewBuilder private func nativePicture(_ owner: MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>,
        playback: MonitorMediaPlaybackModel<MediaFile, PocketPlaybackLook>,
        effects: MonitorFrameEffects) -> some View {
        if let native = source.native {
            MediaPlayerLayerView(player: native.player, session: native.feed,
                qualificationItemToken: { [weak playback = playback] in
                    guard let playback, playback.isActive, playback.ready else { return nil }
                    return playback.token
                },
                effects: effects, transfer: effects.transfer, sampleBus: model.frameSamples)
        }
    }
    private func displaySize(_ playback: MonitorMediaPlaybackModel<MediaFile, PocketPlaybackLook>) -> CGSize {
        if let width = playback.metadata.width, let height = playback.metadata.height {
            return .init(width: width, height: height)
        }
        return PlaybackVideoLayout.size(fromResolution: playback.active?.facts.resolution) ?? .init(width: 16, height: 9)
    }
    private func backdropConfiguration(_ owner: MonitorOperatorMediaModel<MediaFile, PocketPlaybackLook>) -> [MonitorVideoBackdropConfiguration] {
        guard let playback = owner.playback, let native = source.native else { return [] }
        let dimensions = displaySize(playback)
        return [.init(source: ObjectIdentifier(native.feed),
            generation: Int(truncatingIfNeeded: playback.token.revision), effects: model.assist.playbackEffects,
            geometry: [dimensions.width, dimensions.height, pictureGeometry?.zoom.scale ?? 1,
                pictureGeometry?.zoom.offset.width ?? 0, pictureGeometry?.zoom.offset.height ?? 0])]
    }
}

import OpenCineAppKitApple
