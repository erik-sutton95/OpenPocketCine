import OpenPocketViewCore
import SwiftUI
import UniformTypeIdentifiers

/// Built-in / DJI / Custom. 50/50 is pinned on the long-press footer so
/// landscape never hides it under the catalog; the sheet keeps it inline.
/// `embedded` is the assist-tray form; the sheet wraps the same body.
struct LUTPicker: View {
    private enum Category: String, CaseIterable {
        case builtIn = "Built-in"
        case dji = "DJI"
        case custom = "Custom"
    }

    @Bindable var assist: LiveAssistState
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var category: Category = .builtIn
    @State private var importing = false
    @State private var pendingDeletion: String?
    @State private var deletionErrorMessage: String?
    @State private var importError: String?

    /// OpenZCine `LUTPickerContent.contentHeight` — landscape has no headroom for a taller drum.
    private let contentHeight: CGFloat = 146
    private let captionHeight: CGFloat = 28

    var body: some View {
        if embedded {
            picker
        } else {
            NavigationStack {
                picker
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(LiveDesign.background.ignoresSafeArea())
                    .navigationTitle("LUT")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                                .foregroundStyle(LiveDesign.accent)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var picker: some View {
        VStack(spacing: 8) {
            LUTSegmentedButtons(
                items: Category.allCases.map(\.rawValue),
                selected: category.rawValue
            ) { raw in
                guard let next = Category(rawValue: raw), next != category else { return }
                category = next
                switch next {
                case .builtIn:
                    if !assist.lutSelection.isBuiltIn { assist.selectLUT(.auto) }
                case .dji:
                    if !assist.lutSelection.isDJI { assist.selectLUT(.djiAuto) }
                case .custom:
                    break
                }
            }
            tabContent
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight)
            // Embedded long-press parks 50/50 on the panel footer so it
            // stays on screen when the catalog scrolls.
            if !embedded {
                LUTSplitComparisonBar(assist: assist)
            }
            if let importError {
                Text(importError)
                    .font(LiveType.ui(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(StartupColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if assist.lutSelection.isCustom {
                category = .custom
            } else if assist.lutSelection.isDJI {
                category = .dji
            } else {
                category = .builtIn
            }
            assist.syncLUT(
                to: model.session.status.colorMode,
                family: model.session.bodyFamily,
                cameraName: model.session.connectedCamera?.model.name)
        }
        .confirmationDialog(
            pendingDeletion.map { "Clear \(CustomLUTIndex.displayName(fileName: $0))?" }
                ?? "Clear LUT?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button("Clear LUT", role: .destructive) {
                    clear(pendingDeletion)
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the stored LUT from this device. This action cannot be undone.")
        }
        .alert(
            "Couldn’t Delete LUT",
            isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } })
        ) {
            Button("OK") { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "The LUT could not be deleted.")
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]
        ) { result in
            handleImport(result)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch category {
        case .builtIn:
            catalogTab(
                cases: LUTSelection.builtInCases,
                inCatalog: assist.lutSelection.isBuiltIn,
                fallback: .auto,
                caption: builtInCaption
            )
        case .dji:
            catalogTab(
                cases: LUTSelection.djiCases,
                inCatalog: assist.lutSelection.isDJI,
                fallback: .djiAuto,
                caption: djiCaption
            )
        case .custom:
            customTab
        }
    }

    private func catalogTab(
        cases: [LUTSelection],
        inCatalog: Bool,
        fallback: LUTSelection,
        caption: String
    ) -> some View {
        VStack(spacing: 4) {
            Text(caption)
                .font(LiveType.ui(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LiveDesign.muted)
                .multilineTextAlignment(.center)
                .frame(height: captionHeight)
            LUTDrumWheel(
                options: cases.map(\.title),
                selection: Binding(
                    get: {
                        inCatalog ? assist.lutSelection.title : fallback.title
                    },
                    set: { name in
                        guard let selection = cases.first(where: { $0.title == name }) else {
                            return
                        }
                        assist.selectLUT(selection)
                    }
                ),
                wheelHeight: contentHeight - captionHeight - 4
            )
        }
    }

    private var builtInCaption: String {
        if assist.lutSelection == .auto {
            return LUTResolver.autoCaption(source: assist.resolvedSource())
        }
        if assist.lutSelection == .officialDLog {
            return "Built-in D-Log look"
        }
        if assist.lutSelection == .officialDLog2 {
            return "Built-in D-Log2 look"
        }
        return "App looks for this color / camera"
    }

    private var djiCaption: String {
        if assist.lutSelection == .djiAuto {
            return LUTResolver.autoCaption(source: assist.resolvedSource())
        }
        if assist.lutSelection.isDJI {
            return "Official DJI Rec.709 cube"
        }
        return "Official DJI looks for this color / camera"
    }

    @ViewBuilder private var customTab: some View {
        let imported = CustomLUTStore.list()
        VStack(spacing: 6) {
            Button {
                importing = true
            } label: {
                Text("Import .cube")
                    .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiveDesign.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(LiveDesign.glassBright, in: Capsule())
            }
            .buttonStyle(.zcTapTarget)
            if imported.isEmpty {
                Text("Imported looks land here. Auto stays on Built-in or DJI.")
                    .font(LiveType.ui(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiveDesign.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(imported, id: \.fileName) { lut in
                            customFileRow(lut)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func customFileRow(_ lut: StoredCustomLUT) -> some View {
        let selected =
            assist.lutSelection == .customFile
            && OperatorPrefs.selectedCustomFileName == lut.fileName
        return HStack(spacing: 6) {
            Button {
                assist.selectCustomFile(lut.fileName)
            } label: {
                Text(lut.displayName)
                    .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? LiveDesign.accent : LiveDesign.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.zcTapTarget)
            Button {
                pendingDeletion = lut.fileName
            } label: {
                Text("Clear")
                    .font(LiveType.ui(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StartupColors.destructive)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(LiveDesign.glassBright, in: Capsule())
            }
            .buttonStyle(.zcTapTarget)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? LiveDesign.accentDim : LiveDesign.glassBright,
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
        )
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importCube(url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importCube(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let stored = try CustomLUTStore.importFile(from: url)
            guard CustomLUTStore.cube(stored) != nil else {
                try? CustomLUTStore.remove(stored)
                throw CustomLUTStoreError.unreadable
            }
            assist.importCustom(fileName: stored.fileName)
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func clear(_ fileName: String) {
        pendingDeletion = nil
        assist.clearCustomFile(fileName)
    }
}

/// OpenZCine 50/50: off-by-default toggle; orientation chips only while armed.
/// Labels are `Left / Right` and `Top / Bottom`, not Vertical/Horizontal.
///
/// The long-press panel renders this as a pinned footer so opening LUT never
/// hides the control under a catalog scroll.
struct LUTSplitComparisonBar: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        HStack(spacing: 10) {
            Button {
                assist.splitComparison.toggle()
                if assist.splitComparison {
                    if !assist.lutArmed { assist.armLastLUT() }
                }
                assist.persist()
            } label: {
                HStack(spacing: 8) {
                    (assist.splitComparison ? OpcIcon.circleCheck : OpcIcon.circle)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(
                            assist.splitComparison ? LiveDesign.accent : LiveDesign.muted)
                    Text("50/50")
                        .font(LiveType.ui(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiveDesign.text)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    assist.splitComparison
                        ? LiveDesign.accentDim : LiveDesign.glassBright,
                    in: Capsule())
            }
            .buttonStyle(.zcTapTarget)
            if assist.splitComparison {
                LUTSegmentedButtons(
                    items: LUTSplitOrientation.allCases.map(\.rawValue),
                    selected: LUTSplitOrientation.current(vertical: assist.splitVertical).rawValue
                ) { raw in
                    guard let next = LUTSplitOrientation(rawValue: raw) else { return }
                    assist.splitVertical = next.isVertical
                    assist.persist()
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

/// OpenZCine `SplitComparisonOrientation` labels.
private enum LUTSplitOrientation: String, CaseIterable {
    case leftRight = "Left / Right"
    case topBottom = "Top / Bottom"

    var isVertical: Bool { self == .leftRight }

    static func current(vertical: Bool) -> LUTSplitOrientation {
        vertical ? .leftRight : .topBottom
    }
}

/// OpenZCine `SegmentedButtons` — capsule chips, gold when selected.
private struct LUTSegmentedButtons: View {
    let items: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item)
                        .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(item == selected ? LiveDesign.accent : LiveDesign.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            item == selected ? LiveDesign.accentDim : LiveDesign.glassBright,
                            in: Capsule()
                        )
                }
                .buttonStyle(.zcTapTarget)
            }
        }
    }
}

/// OpenZCine `AccentDrumWheel` subset used by the LUT picker (height + delete).
private struct LUTDrumWheel: View {
    let options: [String]
    @Binding var selection: String
    var wheelHeight: CGFloat = 146
    var onDeleteOption: ((String) -> Void)? = nil

    private let rowHeight: CGFloat = 52

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        optionRow(option, isCentered: option == selection)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(
                id: Binding(get: { selection }, set: { if let value = $0 { selection = value } })
            )
            .contentMargins(.vertical, max(0, (wheelHeight - rowHeight) / 2), for: .scrollContent)
            .frame(height: wheelHeight)
            .sensoryFeedback(.selection, trigger: selection)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.22),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                Rectangle().fill(LiveDesign.hairlineStrong).frame(height: 1)
                    .offset(y: -rowHeight / 2)
                Rectangle().fill(LiveDesign.hairlineStrong).frame(height: 1)
                    .offset(y: rowHeight / 2)
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }

    @ViewBuilder private func optionRow(_ option: String, isCentered: Bool) -> some View {
        let row = Text(option)
            .font(
                .system(
                    size: isCentered ? 30 : 23,
                    weight: isCentered ? .semibold : .regular,
                    design: .monospaced)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(isCentered ? LiveDesign.accent : LiveDesign.muted.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .id(option)

        if let onDeleteOption {
            row
                .contextMenu {
                    Button(role: .destructive) {
                        onDeleteOption(option)
                    } label: {
                        Label {
                            Text("Delete LUT")
                        } icon: {
                            OpcIcon.trash
                        }
                    }
                }
                .accessibilityAction(named: Text("Delete \(option)")) {
                    onDeleteOption(option)
                }
        } else {
            row
        }
    }
}
