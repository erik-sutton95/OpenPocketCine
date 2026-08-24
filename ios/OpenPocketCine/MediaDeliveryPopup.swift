import OpenPocketViewCore
import SwiftUI

struct MediaDeliveryPopupOverlay: View {
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
    var onDismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cap = min(
                MediaDeliveryChrome.maxCardHeight, max(240, geo.size.height - 80))
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                MediaDeliveryPopup(
                    files: files,
                    preferredDestination: preferredDestination,
                    onClose: onDismiss
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
                .frame(maxHeight: cap, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

struct MediaDeliveryPopup: View {
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var step: DeliveryStep
    @State private var destination: MediaDeliveryDestination?
    @State private var configuration = MediaDeliveryConfiguration()
    @State private var shareAction: MediaDeliveryPostExportAction = .systemShare
    @State private var statusMessage: String?
    @State private var frameioListing: FrameioProjectListing?
    @State private var frameioProjectsLoading = false
    @State private var frameioProjectsError: String?
    @State private var selectedFrameioProjectID: String?
    @State private var showCreateProjectAlert = false
    @State private var newProjectName = ""
    @State private var showFrameioHopConfirm = false
    @State private var isHoppingForFrameio = false
    @State private var popupStartedHop = false
    @State private var onCameraAP = false

    private enum DeliveryStep { case destination, options }

    init(
        files: [MediaFile],
        preferredDestination: MediaDeliveryDestination? = nil,
        onClose: @escaping () -> Void
    ) {
        self.files = files
        self.preferredDestination = preferredDestination
        self.onClose = onClose
        _destination = State(initialValue: preferredDestination)
        _step = State(initialValue: preferredDestination == nil ? .destination : .options)
    }

    private var session: CameraSession { model.session }
    private var lutAvailable: Bool {
        model.assist.playbackEffects.lutDimension >= 2 || model.assist.effects.lutDimension >= 2
    }
    private var cached: [MediaFile] { files.filter { session.isDownloaded($0) } }
    private var isConnected: Bool {
        if case .live = session.phase { return true }
        return false
    }
    private var selectedFrameioProject: FrameioProject? {
        guard let listing = frameioListing, let id = selectedFrameioProjectID else { return nil }
        return listing.projects.first { $0.id == id }
    }
    private var uploadableFrameioProjects: [FrameioProject] {
        frameioListing?.projects.filter { $0.rootFolderID != nil } ?? []
    }
    private var frameioHopGateActive: Bool { destination == .frameio && onCameraAP }
    private var frameioProjectReady: Bool {
        guard destination == .frameio else { return true }
        guard model.isFrameioConnected else { return false }
        if selectedFrameioProject?.rootFolderID != nil { return true }
        if FrameioDestination.loaded != nil { return true }
        return model.isOnCameraAccessPoint
    }
    private var canContinue: Bool {
        destination != nil
            && (!cached.isEmpty || (isConnected && !files.isEmpty))
            && !(configuration.bakeLUT && !lutAvailable)
            && !(destination == .frameio && !frameioProjectReady)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    switch step {
                    case .destination: destinations
                    case .options: options
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(LiveType.ui(size: 12))
                            .foregroundStyle(LiveDesign.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            if step == .options, !frameioHopGateActive {
                footer.padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous),
            interactive: false
        )
        .onAppear {
            if !lutAvailable { configuration.bakeLUT = false }
            if let saved = FrameioDestination.loaded {
                selectedFrameioProjectID = saved.projectID
            }
            onCameraAP = model.isOnCameraAccessPoint
        }
        .alert("New Frame.io project", isPresented: $showCreateProjectAlert) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { newProjectName = "" }
            Button("Create") {
                let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                newProjectName = ""
                guard !name.isEmpty else { return }
                Task { await createFrameioProject(named: name) }
            }
            .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Creates a blank project in your workspace.")
        }
        .alert("Leave camera Wi‑Fi?", isPresented: $showFrameioHopConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Hop") { startFrameioHop() }
        } message: {
            Text(
                "We'll hop to home Wi‑Fi or cellular so you can sign in and pick a project. The camera reconnects automatically when you're done."
            )
        }
    }

    private var header: some View {
        Group {
            switch step {
            case .destination:
                HStack(spacing: 10) {
                    Label {
                        Text("Share")
                    } icon: {
                        OpcIcon.share
                            .frame(width: 13, height: 13)
                    }
                    .font(LiveType.display(14, weight: .bold))
                    .kerning(1)
                    .textCase(.uppercase)
                    .foregroundStyle(LiveDesign.text)
                    Spacer(minLength: 0)
                    CloseButton(action: closePopup, size: 30)
                }
            case .options:
                HStack(spacing: 10) {
                    Button {
                        step = .destination
                    } label: {
                        Label {
                            Text("Back")
                        } icon: {
                            OpcIcon.chevronLeft
                                .frame(width: 12, height: 12)
                        }
                        .font(LiveType.ui(size: 13, weight: .semibold))
                        .foregroundStyle(LiveDesign.accent)
                    }
                    .buttonStyle(.zcTapTarget)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination?.title ?? "Share")
                            .font(LiveType.ui(size: 15, weight: .semibold))
                            .foregroundStyle(LiveDesign.text)
                        Text("Options")
                            .font(LiveType.ui(size: 11, weight: .medium))
                            .foregroundStyle(LiveDesign.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(files.count) clip\(files.count == 1 ? "" : "s")")
                .font(LiveType.ui(size: 15, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
            if cached.count < files.count {
                Text(
                    isConnected
                        ? "\(files.count - cached.count) on-camera clip(s) will be cached from the camera first."
                        : "\(files.count - cached.count) on-camera clip(s) will be skipped — reconnect the camera to cache them."
                )
                .font(LiveType.ui(size: 12))
                .foregroundStyle(LiveDesign.muted)
            }
            if destination == .frameio, !model.isFrameioConfigured {
                Text("Frame.io isn't configured — add credentials in Settings → Storage.")
                    .font(LiveType.ui(size: 12))
                    .foregroundStyle(LiveDesign.accent)
            } else if destination == .frameio,
                let name = selectedFrameioProject?.name
                    ?? FrameioDestination.loaded?.projectName, step == .options
            {
                Text("Project: \(name)")
                    .font(LiveType.ui(size: 12))
                    .foregroundStyle(LiveDesign.muted)
            }
        }
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("DESTINATION")
            ForEach(MediaDeliveryDestination.allCases) { candidate in
                destinationRow(candidate)
            }
        }
    }

    private func destinationRow(_ candidate: MediaDeliveryDestination) -> some View {
        let enabled = isDestinationEnabled(candidate)
        return Button {
            guard enabled else { return }
            destination = candidate
            step = .options
            if candidate == .frameio {
                Task { await loadFrameioProjects() }
            }
        } label: {
            HStack(spacing: 12) {
                destinationIcon(candidate)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(LiveType.ui(size: 14, weight: .semibold))
                        .foregroundStyle(enabled ? LiveDesign.text : LiveDesign.faint)
                    Text(
                        candidate == .frameio && model.isFrameioConfigured
                            && !model.isFrameioConnected
                            ? "Sign in from Settings → Storage first."
                            : candidate.subtitle
                    )
                    .font(LiveType.ui(size: 11))
                    .foregroundStyle(LiveDesign.muted)
                }
                Spacer()
                OpcIcon.chevronRight
                    .frame(width: 12, height: 12)
                    .foregroundStyle(LiveDesign.faint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LiveDesign.hairline.opacity(0.35),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
        }
        .buttonStyle(.zcTapTarget)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func destinationIcon(_ candidate: MediaDeliveryDestination) -> some View {
        switch candidate {
        case .nativeShare:
            OpcIcon.share
                .frame(width: 18, height: 18)
                .foregroundStyle(LiveDesign.text)
        case .frameio:
            FrameioMark()
                .foregroundStyle(model.isFrameioConfigured ? LiveDesign.text : LiveDesign.faint)
        }
    }

    private func isDestinationEnabled(_ candidate: MediaDeliveryDestination) -> Bool {
        let hasDeliverable = !cached.isEmpty || (isConnected && !files.isEmpty)
        switch candidate {
        case .nativeShare: return hasDeliverable
        case .frameio:
            return model.isFrameioConfigured && model.isFrameioConnected && hasDeliverable
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 18) {
            if destination == .frameio {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(frameioHopGateActive ? "FRAME.IO" : "PROJECT")
                    if frameioHopGateActive {
                        frameioHopGate
                    } else {
                        frameioProjectPicker
                    }
                }
            }
            if !frameioHopGateActive {
                exportSection
            }
        }
        .onAppear { onCameraAP = model.isOnCameraAccessPoint }
        .task {
            while !Task.isCancelled {
                onCameraAP = model.isOnCameraAccessPoint
                if destination == .frameio, model.isFrameioConfigured, model.isFrameioConnected,
                    !onCameraAP, frameioListing == nil, !frameioProjectsLoading,
                    frameioProjectsError == nil
                {
                    await loadFrameioProjects()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder private var frameioHopGate: some View {
        Text(
            FrameioDestination.loaded.map {
                "Frame.io needs the internet. Hop off the camera's Wi‑Fi to pick a project (currently “\($0.projectName)”) and upload — the camera reconnects automatically when you're done."
            }
                ?? "Frame.io needs the internet. Hop off the camera's Wi‑Fi to sign in and pick a project — the camera reconnects automatically when you're done."
        )
        .font(LiveType.ui(size: 13))
        .foregroundStyle(LiveDesign.muted)
        .fixedSize(horizontal: false, vertical: true)

        if isHoppingForFrameio {
            HStack(spacing: 8) {
                ProgressView().tint(LiveDesign.accent)
                Text("Switching networks…")
                    .font(LiveType.ui(size: 13))
                    .foregroundStyle(LiveDesign.muted)
            }
        } else {
            Button {
                showFrameioHopConfirm = true
            } label: {
                Label {
                    Text("Hop to internet")
                } icon: {
                    OpcIcon.wifiOff
                        .frame(width: 16, height: 16)
                }
                .font(LiveType.ui(size: 15, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LiveDesign.accent.opacity(0.22),
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous
                    )
                    .strokeBorder(LiveDesign.accent.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.zcTapTarget)
        }
    }

    private var frameioProjectPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("Project")
                    .font(LiveType.ui(size: 14, weight: .semibold))
                    .foregroundStyle(LiveDesign.text)
                HelpBadge(text: "Upload destination in your Frame.io workspace.")
            }
            if !model.isFrameioConnected {
                Text("Sign in to Frame.io from Settings → Storage to upload.")
                    .font(LiveType.ui(size: 12))
                    .foregroundStyle(LiveDesign.muted)
            }
            if frameioProjectsLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(LiveDesign.accent)
                    Text("Loading projects…")
                        .font(LiveType.ui(size: 12))
                        .foregroundStyle(LiveDesign.muted)
                }
            } else if let frameioProjectsError {
                Text(frameioProjectsError)
                    .font(LiveType.ui(size: 12))
                    .foregroundStyle(LiveDesign.accent)
                Button("Retry") { Task { await loadFrameioProjects() } }
                    .font(LiveType.ui(size: 13, weight: .semibold))
                    .foregroundStyle(LiveDesign.accent)
            } else if frameioListing != nil {
                frameioProjectMenu
                Button {
                    newProjectName = ""
                    showCreateProjectAlert = true
                } label: {
                    HStack(spacing: 10) {
                        OpcIcon.circlePlus
                            .frame(width: 16, height: 16)
                            .foregroundStyle(LiveDesign.accent)
                        Text("Create new project")
                            .font(LiveType.ui(size: 13, weight: .semibold))
                            .foregroundStyle(LiveDesign.text)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        LiveDesign.hairline.opacity(0.35),
                        in: RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous))
                }
                .buttonStyle(.zcTapTarget)
            }
        }
    }

    private var frameioProjectMenu: some View {
        Menu {
            if uploadableFrameioProjects.isEmpty {
                Button("No projects") {}.disabled(true)
            } else {
                ForEach(uploadableFrameioProjects) { project in
                    Button {
                        selectFrameioProject(project)
                    } label: {
                        if selectedFrameioProjectID == project.id {
                            Label {
                                Text(project.name)
                            } icon: {
                                OpcIcon.check
                            }
                        } else {
                            Text(project.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                OpcIcon.folder
                    .frame(width: 14, height: 14)
                    .foregroundStyle(LiveDesign.muted)
                Text(selectedFrameioProject?.name ?? "Select a project")
                    .font(LiveType.ui(size: 13, weight: .semibold))
                    .foregroundStyle(
                        selectedFrameioProject != nil ? LiveDesign.text : LiveDesign.muted
                    )
                    .lineLimit(1)
                Spacer()
                OpcIcon.chevronsUpDown
                    .frame(width: 11, height: 11)
                    .foregroundStyle(LiveDesign.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LiveDesign.hairline.opacity(0.35),
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
        }
        .buttonStyle(.zcTapTarget)
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("EXPORT")
            if let file = files.first, files.count == 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filename")
                        .font(LiveType.ui(size: 12, weight: .semibold))
                        .foregroundStyle(LiveDesign.muted)
                    Text(MediaDelivery.filename(for: file, configuration: configuration))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(LiveDesign.text)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LiveDesign.hairline.opacity(0.35),
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous))
            }
            toggleRow(
                MediaDeliveryCopy.bakeLUT,
                help: lutAvailable
                    ? MediaDeliveryCopy.bakeLUTHelp(statusLabel: model.assist.lutStatusLabel)
                    : MediaDeliveryCopy.bakeLUTHelpUnavailable,
                isOn: $configuration.bakeLUT,
                enabled: lutAvailable)
            if configuration.bakeLUT {
                toggleRow(
                    MediaDeliveryCopy.bakeExposure,
                    help: MediaDeliveryCopy.bakeExposureHelp,
                    isOn: $configuration.bakeLUTExposure,
                    enabled: lutAvailable)
            }
            if configuration.bakeLUT || destination == .nativeShare {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Format")
                            .font(LiveType.ui(size: 14, weight: .semibold))
                            .foregroundStyle(LiveDesign.text)
                        HelpBadge(
                            text:
                                "Export container — MOV preserves quality; MP4 is more widely compatible."
                        )
                    }
                    Picker("Format", selection: $configuration.exportFormat) {
                        ForEach(MediaExportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
                .background(
                    LiveDesign.hairline.opacity(0.35),
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous))
            }
            toggleRow(
                "Include metadata",
                help: "Filename, capture date, and size (best-effort JSON sidecar).",
                isOn: $configuration.includeMetadata,
                enabled: true)
            if destination == .frameio {
                toggleRow(
                    "Re-upload already uploaded",
                    help: "Skip clips already on Frame.io unless enabled.",
                    isOn: $configuration.forceFrameioReupload,
                    enabled: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if destination == .nativeShare {
                Picker("Delivery action", selection: $shareAction) {
                    Text("Share").tag(MediaDeliveryPostExportAction.systemShare)
                    Text("Save to Photos").tag(MediaDeliveryPostExportAction.saveToPhotos)
                }
                .pickerStyle(.segmented)
            }
            Button {
                beginDelivery()
            } label: {
                Text(actionTitle)
                    .font(LiveType.ui(size: 15, weight: .semibold))
                    .foregroundStyle(canContinue ? LiveDesign.text : LiveDesign.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        canContinue
                            ? LiveDesign.accent.opacity(0.22) : LiveDesign.hairline.opacity(0.25),
                        in: RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous
                        )
                        .strokeBorder(
                            canContinue
                                ? LiveDesign.accent.opacity(0.55)
                                : LiveDesign.hairline.opacity(0.35),
                            lineWidth: 1))
            }
            .buttonStyle(.zcTapTarget)
            .disabled(!canContinue)
        }
    }

    private var actionTitle: String {
        switch destination {
        case .nativeShare:
            shareAction == .saveToPhotos ? "Save to Photos" : "Share"
        case .frameio:
            destination?.actionTitle ?? "Upload"
        case .none:
            "Continue"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .kerning(0.6)
            .foregroundStyle(LiveDesign.faint)
    }

    private func toggleRow(
        _ title: String, help: String, isOn: Binding<Bool>, enabled: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(LiveType.ui(size: 14, weight: .semibold))
                        .foregroundStyle(enabled ? LiveDesign.text : LiveDesign.faint)
                    HelpBadge(text: help)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(LiveDesign.accent)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(
            LiveDesign.hairline.opacity(0.35),
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func beginDelivery() {
        guard let destination else { return }
        popupStartedHop = false
        let request = MediaDeliveryBeginRequest(
            files: files,
            destination: destination,
            configuration: configuration,
            postExportAction: shareAction)
        onClose()
        model.delivery.begin(request, model: model)
    }

    private func closePopup() {
        if popupStartedHop { model.endInternetHop() }
        onClose()
    }

    private func startFrameioHop() {
        isHoppingForFrameio = true
        popupStartedHop = true
        model.beginInternetHop()
        Task {
            let online = await model.waitForInternetPath(timeoutSeconds: 30)
            isHoppingForFrameio = false
            if online {
                await loadFrameioProjects()
            } else {
                frameioProjectsError =
                    "Couldn't reach the internet after leaving the camera's Wi‑Fi. Check cellular or home Wi‑Fi."
            }
        }
    }

    private func loadFrameioProjects() async {
        guard !model.isOnCameraAccessPoint else { return }
        frameioProjectsLoading = true
        frameioProjectsError = nil
        defer { frameioProjectsLoading = false }
        do {
            let listing = try await model.loadFrameioProjectListing()
            frameioListing = listing
            if selectedFrameioProjectID == nil {
                selectedFrameioProjectID =
                    FrameioDestination.loaded?.projectID ?? listing.projects.first?.id
            }
            if let project = selectedFrameioProject {
                selectFrameioProject(project)
            }
        } catch {
            frameioProjectsError = error.localizedDescription
        }
    }

    private func selectFrameioProject(_ project: FrameioProject) {
        selectedFrameioProjectID = project.id
        if let listing = frameioListing {
            model.persistFrameioDestination(
                project: project, accountID: listing.accountID, workspaceID: listing.workspaceID)
        }
    }

    private func createFrameioProject(named name: String) async {
        guard let listing = frameioListing else { return }
        do {
            let project = try await model.createFrameioProject(
                name: name, accountID: listing.accountID, workspaceID: listing.workspaceID)
            frameioListing?.projects.insert(project, at: 0)
            selectFrameioProject(project)
        } catch {
            frameioProjectsError = error.localizedDescription
        }
    }
}
