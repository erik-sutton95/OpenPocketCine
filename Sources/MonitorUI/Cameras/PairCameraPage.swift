#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Native rail-and-pane pairing presentation. The adapter reports each completed
    /// stage; only its actions can connect, retry, or cancel the real camera session.
    public struct PairCameraPage: View {
        public var presentation: CameraPairingPresentation
        public var safeArea: EdgeInsets
        public var onSelect: (String) -> Void
        public var onPrimary: () -> Void
        public var onBack: () -> Void
        public var onDiagnostics: () -> Void
        public var onWatchFeed: (() -> Void)?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        public init(
            presentation: CameraPairingPresentation, safeArea: EdgeInsets = EdgeInsets(),
            onSelect: @escaping (String) -> Void, onPrimary: @escaping () -> Void,
            onBack: @escaping () -> Void, onDiagnostics: @escaping () -> Void,
            onWatchFeed: (() -> Void)? = nil
        ) {
            self.presentation = presentation
            self.safeArea = safeArea
            self.onSelect = onSelect
            self.onPrimary = onPrimary
            self.onBack = onBack
            self.onDiagnostics = onDiagnostics
            self.onWatchFeed = onWatchFeed
        }

        @Environment(\.monitorWindowGeometry) private var windowGeometry

        public var body: some View {
            GeometryReader { proxy in
                let portrait = proxy.size.height > proxy.size.width
                let tablet = min(proxy.size.width, proxy.size.height) >= 600
                Group {
                    if portrait {
                        VStack(spacing: 10) {
                            rail(portrait: true)
                            pane(portrait: true, tablet: tablet)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            rail(portrait: false).frame(width: tablet ? 268 : 210)
                            pane(portrait: false, tablet: tablet)
                        }
                    }
                }
                .padding(.top, safeArea.top + windowGeometry.topControlInset + 12)
                .padding(.leading, safeArea.leading + 14)
                .padding(.trailing, safeArea.trailing + 14)
                .padding(.bottom, safeArea.bottom + 12)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(MonitorTheme.background).foregroundStyle(.white)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16), value: presentation.currentStep)
        }

        private func rail(portrait: Bool) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    if presentation.backAction != nil {
                        Button(action: onBack) {
                            CameraPageGlyph(icon: .back).stroke(
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 13, height: 13).frame(width: 32, height: 32)
                            .background(MonitorTheme.secondary.opacity(0.12), in: Circle())
                            .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(
                            presentation.backAction ?? "Your cameras")
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("STEP \(presentation.currentStep + 1) OF \(presentation.steps.count)")
                            .font(MonitorTheme.font(8, weight: .bold)).tracking(1.4)
                            .foregroundStyle(MonitorTheme.accent)
                        Text("Pair a camera").font(MonitorTheme.font(13, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Share Diagnostics", action: onDiagnostics)
                        if let onWatchFeed { Button("Watch a feed", action: onWatchFeed) }
                    } label: {
                        CameraPageGlyph(icon: .more).stroke(lineWidth: 1.8).frame(
                            width: 15, height: 15
                        ).frame(width: 32, height: 44)
                    }.accessibilityLabel("Pairing help and diagnostics")
                }
                Group {
                    if portrait {
                        HStack(spacing: 3) {
                            ForEach(Array(presentation.steps.enumerated()), id: \.element.id) {
                                index, step in
                                stepRow(step, index: index, portrait: true)
                            }
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 3) {
                                ForEach(Array(presentation.steps.enumerated()), id: \.element.id) {
                                    index, step in
                                    stepRow(step, index: index, portrait: false)
                                }
                            }
                        }.frame(maxHeight: .infinity)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("TARGET").font(MonitorTheme.font(8, weight: .bold)).tracking(1.3)
                        .foregroundStyle(MonitorTheme.faint)
                    Text(presentation.target).font(MonitorTheme.font(10, weight: .semibold))
                        .foregroundStyle(MonitorTheme.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(
                    .vertical, 9
                )
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(
                        Color.white.opacity(0.06), lineWidth: 1))
            }
            .padding(11).frame(
                maxWidth: .infinity, maxHeight: portrait ? nil : .infinity, alignment: .topLeading
            )
            .background(MonitorTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
        }

        private func stepRow(_ step: CameraPairingStep, index: Int, portrait: Bool) -> some View {
            let active = index == presentation.currentStep
            let complete = index < presentation.currentStep
            return HStack(spacing: 9) {
                Text(complete ? "✓" : "\(index + 1)")
                    .font(MonitorTheme.font(9.5, weight: .bold))
                    .foregroundStyle(
                        complete
                            ? MonitorTheme.background
                            : active ? MonitorTheme.accent : MonitorTheme.faint
                    )
                    .frame(width: 20, height: 20)
                    .background(
                        complete
                            ? MonitorTheme.accent
                            : active
                                ? MonitorTheme.accent.opacity(0.24) : Color.white.opacity(0.06),
                        in: Circle())
                if !portrait {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title).font(MonitorTheme.font(12, weight: .semibold))
                            .foregroundStyle(
                                active
                                    ? .white
                                    : complete ? MonitorTheme.secondary : MonitorTheme.faint)
                        Text(step.subtitle).font(MonitorTheme.font(8.5)).tracking(0.6)
                            .foregroundStyle(MonitorTheme.faint)
                    }.frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                }
            }
            .padding(.horizontal, 9).frame(
                maxWidth: .infinity, minHeight: portrait ? 34 : 42,
                alignment: portrait ? .center : .leading
            )
            .background(
                active ? MonitorTheme.accent.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Step \(index + 1): \(step.title), \(complete ? "complete" : active ? "current" : "waiting")"
            )
        }

        private func pane(portrait: Bool, tablet: Bool) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.title).font(
                        MonitorTheme.font(tablet ? 25 : 19, weight: .semibold)
                    )
                    .tracking(-0.2).fixedSize(horizontal: false, vertical: true)
                    Text(presentation.body).font(MonitorTheme.font(12.5)).foregroundStyle(
                        MonitorTheme.muted
                    )
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = presentation.error {
                            Text(error).font(MonitorTheme.font(12)).foregroundStyle(
                                MonitorTheme.secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(
                                MonitorTheme.recording.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11))
                        }
                        ForEach(presentation.devices) { device in discoveryRow(device) }
                        if let emptyTitle = presentation.emptyTitle {
                            Text(emptyTitle).font(MonitorTheme.font(13, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                                .background(
                                    Color.white.opacity(0.03),
                                    in: RoundedRectangle(cornerRadius: 11))
                        }
                        ForEach(presentation.instructions) { instruction in
                            instructionCard(instruction)
                        }
                        ForEach(presentation.checks) { check in checkRow(check) }
                        if !presentation.summary.isEmpty {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(), alignment: .leading),
                                    count: portrait || tablet ? 2 : 3), spacing: 8
                            ) {
                                ForEach(presentation.summary) { detail in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(detail.title.uppercased()).font(
                                            MonitorTheme.font(8, weight: .bold)
                                        ).tracking(1.3).foregroundStyle(MonitorTheme.faint)
                                        Text(detail.value).font(
                                            MonitorTheme.font(11, weight: .semibold)
                                        ).foregroundStyle(MonitorTheme.secondary).lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(
                                            Color.white.opacity(0.03),
                                            in: RoundedRectangle(cornerRadius: 11))
                                }
                            }
                        }
                        if let progress = presentation.progress {
                            CameraProgressLabel(title: progress).padding(.top, 3)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer(portrait: portrait)
            }
            .padding(.horizontal, tablet ? 20 : 15).padding(.top, tablet ? 18 : 14).padding(
                .bottom, tablet ? 14 : 12
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.04), lineWidth: 1))
        }

        private func discoveryRow(_ device: CameraListItem) -> some View {
            Button {
                onSelect(device.id)
            } label: {
                HStack(spacing: 11) {
                    Circle().fill(device.isPrimary ? MonitorTheme.accent : MonitorTheme.faint)
                        .frame(width: 7, height: 7).frame(width: 26, height: 26)
                        .background(
                            device.isPrimary
                                ? MonitorTheme.accent.opacity(0.16) : Color.white.opacity(0.05),
                            in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(MonitorTheme.font(13.5, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(device.subtitle).font(MonitorTheme.font(9.5)).foregroundStyle(
                            MonitorTheme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    if let bars = device.signalBars { CameraSignalBars(count: bars) }
                }
                .padding(.horizontal, 13).padding(.vertical, 12)
                .background(
                    device.isPrimary
                        ? MonitorTheme.accent.opacity(0.08) : Color.white.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11).stroke(
                        device.isPrimary
                            ? MonitorTheme.accent.opacity(0.5) : Color.white.opacity(0.06),
                        lineWidth: device.isPrimary ? 1.5 : 1))
            }
            .buttonStyle(.plain).disabled(device.isBusy)
            .accessibilityLabel("Connect \(device.name)")
            .accessibilityIdentifier("pair.device.\(device.id)")
        }

        private func instructionCard(_ instruction: CameraPairingInstruction) -> some View {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    CameraPageGlyph(icon: instruction.icon == .camera ? .camera : .phone)
                        .stroke(
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 14, height: 14).foregroundStyle(MonitorTheme.accent).frame(
                            width: 26, height: 26
                        )
                        .background(
                            MonitorTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)
                        )
                    Text(instruction.title.uppercased()).font(MonitorTheme.font(9, weight: .bold))
                        .tracking(1.4)
                }
                ForEach(instruction.lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(MonitorTheme.faint)
                        Text(line).font(MonitorTheme.font(12.5)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .foregroundStyle(MonitorTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }

        private func checkRow(_ check: CameraPairingCheck) -> some View {
            HStack(spacing: 11) {
                Text(check.state == .complete ? "✓" : check.state == .active ? "·" : "")
                    .font(MonitorTheme.font(10, weight: .bold))
                    .foregroundStyle(
                        check.state == .complete ? MonitorTheme.background : MonitorTheme.accent
                    )
                    .frame(width: 22, height: 22)
                    .background(
                        check.state == .complete
                            ? MonitorTheme.accent
                            : MonitorTheme.accent.opacity(check.state == .active ? 0.16 : 0.04),
                        in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title).font(MonitorTheme.font(13, weight: .semibold))
                    Text(check.subtitle).font(MonitorTheme.font(9.5)).foregroundStyle(
                        MonitorTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(check.stateLabel).font(MonitorTheme.font(8.5, weight: .bold)).tracking(1.1)
                    .foregroundStyle(
                        check.state == .complete
                            ? Color(red: 63 / 255, green: 211 / 255, blue: 163 / 255)
                            : check.state == .active ? MonitorTheme.accent : MonitorTheme.faint)
            }
            .padding(13).background(
                Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }

        private func footer(portrait: Bool) -> some View {
            VStack(spacing: 9) {
                if portrait {
                    Text(presentation.hint).font(MonitorTheme.font(9.5)).foregroundStyle(
                        MonitorTheme.faint
                    )
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 9) {
                    if !portrait {
                        Text(presentation.hint).font(MonitorTheme.font(9.5)).foregroundStyle(
                            MonitorTheme.faint
                        ).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    if let back = presentation.backAction {
                        Button(back, action: onBack).buttonStyle(CameraPageButtonStyle())
                    }
                    if let primary = presentation.primaryAction {
                        Button(primary, action: onPrimary).buttonStyle(
                            CameraPageButtonStyle(primary: true)
                        )
                        .disabled(!presentation.primaryActionEnabled)
                    }
                }
            }.frame(maxWidth: .infinity)
        }
    }
#endif
