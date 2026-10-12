import SwiftUI

/// Five recognizable chapter icons form a compact progress strip in the header.
struct SessionJourneyProgressBar: View {
    @Bindable var model: SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        JourneyBarControl(phase: model.session.phase,
                          reached: Set(model.session.reachedPhases.keys),
                          isExpanded: $isExpanded,
                          onSelect: select)
            .popover(isPresented: $isExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                JourneyProgressMenu(phase: model.session.phase,
                                    reached: Set(model.session.reachedPhases.keys),
                                    onSelect: select,
                                    onClose: { isExpanded = false })
                    .presentationBackground(Palette.surface)
                    .presentationCornerRadius(24)
            }
            .onChange(of: model.session.phase) { _, _ in isExpanded = false }
    }

    private func select(_ phase: SessionPhase) {
        guard phase == model.session.phase || model.session.reachedPhases[phase] != nil else { return }
        if phase != model.session.phase {
            if model.session.phase == .check { model.coach.pauseReview() }
            withAnimation(reduceMotion ? nil : .stopMotion(duration: 0.28, fps: 15)) {
                model.advance(to: phase)
            }
        }
        isExpanded = false
    }
}

/// A persistent, quiet left-edge chapter rail. Visited markers navigate directly;
/// the selected marker reveals the complete labeled journey beside the rail.
struct SessionJourneyRail: View {
    @Bindable var model: SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        JourneyRailControl(phase: model.session.phase,
                           reached: Set(model.session.reachedPhases.keys),
                           isExpanded: $isExpanded,
                           onSelect: select)
            .popover(isPresented: $isExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .leading) {
                JourneyProgressMenu(phase: model.session.phase,
                                    reached: Set(model.session.reachedPhases.keys),
                                    onSelect: select,
                                    onClose: { isExpanded = false })
                    .presentationBackground(Palette.surface)
                    .presentationCornerRadius(24)
            }
            .onChange(of: model.session.phase) { _, _ in isExpanded = false }
    }

    private func select(_ phase: SessionPhase) {
        guard phase == model.session.phase || model.session.reachedPhases[phase] != nil else { return }
        if phase != model.session.phase {
            // A delayed review answer must not mutate the map after leaving Reflect.
            if model.session.phase == .check { model.coach.pauseReview() }
            withAnimation(reduceMotion ? nil : .stopMotion(duration: 0.28, fps: 15)) {
                model.advance(to: phase)
            }
        }
        isExpanded = false
    }
}

/// A small paper chapter marker opens the full, revisitable study journey.
/// Reaching a phase means it was visited, not that its learning work is complete.
struct SessionJourneyProgress: View {
    @Bindable var model: SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        JourneyProgressControl(
            phase: model.session.phase,
            reached: Set(model.session.reachedPhases.keys),
            isExpanded: $isExpanded
        )
        .popover(isPresented: $isExpanded, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            JourneyProgressMenu(
                phase: model.session.phase,
                reached: Set(model.session.reachedPhases.keys),
                onSelect: { phase in
                    guard phase == model.session.phase || model.session.reachedPhases[phase] != nil else { return }
                    withAnimation(reduceMotion ? nil : .stopMotion(duration: 0.32, fps: 15)) {
                        if phase != model.session.phase {
                            model.coach.pauseReview()
                            model.conversation.close()
                            model.advance(to: phase)
                        }
                        isExpanded = false
                    }
                },
                onClose: { isExpanded = false }
            )
            .presentationBackground(Palette.surface)
            .presentationCornerRadius(24)
        }
    }
}

/// Kept independent of the session store so previews exercise the real UI states.
private struct JourneyBarControl: View {
    let phase: SessionPhase
    let reached: Set<SessionPhase>
    @Binding var isExpanded: Bool
    var onSelect: (SessionPhase) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Namespace private var activeTab

    var body: some View {
        GeometryReader { geometry in
            let showsLabels = geometry.size.width >= 350 && !dynamicType.isAccessibilitySize
            HStack(spacing: 6) {
                ForEach(SessionPhase.allCases) { item in
                    VStack(spacing: 4) {
                        marker(item, showsLabel: showsLabels)
                        Capsule()
                            .fill(item == phase ? Palette.ink : reached.contains(item) ? Palette.oliveDeep : Palette.hairline)
                            .frame(height: 2)
                            .padding(.horizontal, 6)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Palette.surface.opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.75)
                    }
            }
        }
        .frame(minWidth: 256, maxWidth: .infinity)
        .frame(height: 74)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: phase)
        .sensoryFeedback(.selection, trigger: phase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Study journey"))
        .accessibilityIdentifier("journey.bar")
    }

    private func marker(_ item: SessionPhase, showsLabel: Bool) -> some View {
        let current = item == phase
        let available = current || reached.contains(item)
        return Button {
            if current { isExpanded.toggle() } else { onSelect(item) }
        } label: {
            VStack(spacing: 2) {
                JourneyPencilIcon(phase: item)
                    .frame(width: 34, height: 34)
                    .opacity(current ? 1 : available ? 0.86 : 0.38)
                if showsLabel {
                    Text(item.title)
                        .font(.caption2.weight(current ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .foregroundStyle(current ? Palette.ink : available ? Palette.ink2 : Palette.ink3)
            .frame(minWidth: 44, maxWidth: .infinity)
            .frame(height: 56)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.highlighter)
                        .matchedGeometryEffect(id: "pencil-current", in: activeTab)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(JourneyPressStyle())
        .disabled(!available)
        .help(item.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(item.rawValue + 1), \(item.title)"))
        .accessibilityValue(Text(current ? "Current step" : available ? "Visited" : "Not yet available"))
        .accessibilityHint(Text(current ? String(localized: "Opens all steps.") : available ?
                                String(localized: "Returns to this step.") :
                                String(localized: "Continue through the earlier steps to unlock.")))
        .accessibilityAddTraits(current ? [.isSelected] : [])
        .accessibilityIdentifier("journey.marker.\(item.rawValue)")
    }
}

private struct JourneyPencilIcon: View {
    let phase: SessionPhase

    var body: some View {
        Image(phase.journeyPencilAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

private struct JourneyProgressControl: View {
    let phase: SessionPhase
    let reached: Set<SessionPhase>
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 38

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: 11) {
                ZStack {
                    JourneyPaperShape().fill(Palette.highlighter)
                        .rotationEffect(.degrees(-4))
                    Image(systemName: phase.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .contentTransition(.opacity)
                }
                .frame(width: iconSize, height: iconSize)

                VStack(alignment: .leading, spacing: 6) {
                    Text(phase.title)
                        .font(TypeScale.heading(17))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    HStack(spacing: 4) {
                        ForEach(SessionPhase.allCases) { item in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(item == phase ? Palette.ink :
                                        reached.contains(item) ? Palette.oliveDeep : Palette.hairline)
                                .frame(width: item == phase ? 25 : 13, height: 3)
                                .offset(y: item == phase ? -1 : 0)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .frame(minWidth: 96, alignment: .leading)

                JourneyPerforation()
                    .stroke(Palette.ink3.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: 1, height: 28)
                    .padding(.horizontal, 1)

                VStack(spacing: 1) {
                    Text(phase.journeyNumber)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("/ 05")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.ink2)
                }
                .monospacedDigit()
                .accessibilityHidden(true)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .foregroundStyle(Palette.ink2)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 15)
                    .fill(Palette.ink.opacity(0.12))
                    .offset(y: 2)
                RoundedRectangle(cornerRadius: 15)
                    .fill(Palette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(Palette.ink.opacity(0.12), lineWidth: 0.75)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(JourneyPressStyle())
        .animation(reduceMotion ? nil : .stopMotion(duration: 0.32, fps: 15), value: phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
        .sensoryFeedback(.selection, trigger: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Study journey"))
        .accessibilityValue(Text("Step \(phase.rawValue + 1) of 5, \(phase.title)"))
        .accessibilityHint(Text("Opens all steps and lets you return to a visited step."))
        .accessibilityIdentifier("journey.progress")
    }
}

private struct JourneyRailControl: View {
    let phase: SessionPhase
    let reached: Set<SessionPhase>
    @Binding var isExpanded: Bool
    var onSelect: (SessionPhase) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: SessionPhase?
    @Namespace private var markerSelection

    var body: some View {
        ViewThatFits(in: .vertical) {
            markers.fixedSize(horizontal: true, vertical: true)
            compactControl
        }
        .frame(width: 44)
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .stopMotion(duration: 0.28, fps: 15), value: phase)
        .sensoryFeedback(.selection, trigger: phase)
        .accessibilityIdentifier("journey.rail")
    }

    private var markers: some View {
        VStack(spacing: 0) {
            ForEach(SessionPhase.allCases) { item in
                marker(item)
            }
        }
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Palette.surface.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Palette.ink.opacity(0.07), lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Study journey"))
    }

    private func marker(_ item: SessionPhase) -> some View {
        let current = item == phase
        let available = current || reached.contains(item)

        return Button {
            if current { isExpanded.toggle() } else { onSelect(item) }
        } label: {
            ZStack {
                if current {
                    JourneyPaperShape()
                        .fill(Palette.highlighter)
                        .frame(width: 34, height: 30)
                        .matchedGeometryEffect(id: "rail-current", in: markerSelection)
                }
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(current ? Palette.ink : available ? Palette.ink2 : Palette.hairline)
                    .frame(width: current ? 22 : available ? 14 : 10, height: current ? 3.5 : 3)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(JourneyPressStyle())
        .disabled(!available)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                hovered = inside ? item : nil
            }
        }
        .overlay(alignment: .leading) {
            if hovered == item && !isExpanded {
                Text(item.title)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .offset(x: 52)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(item.rawValue + 1), \(item.title)"))
        .accessibilityValue(Text(current ? "Current step" : available ? "Visited" : "Not yet available"))
        .accessibilityHint(Text(current ? String(localized: "Opens all steps.") : available ?
                                String(localized: "Returns to this step.") :
                                String(localized: "Continue through the earlier steps to unlock.")))
        .accessibilityAddTraits(current ? [.isSelected] : [])
        .accessibilityIdentifier("journey.marker.\(item.rawValue)")
    }

    /// Preserve the available board height when the software keyboard leaves
    /// too little room for five non-overlapping 44pt touch targets.
    private var compactControl: some View {
        Button { isExpanded.toggle() } label: {
            VStack(spacing: 3) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                Text(phase.journeyNumber)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44)
            .background(Palette.highlighter, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(JourneyPressStyle())
        .accessibilityLabel(Text("Study journey"))
        .accessibilityValue(Text("Step \(phase.rawValue + 1) of 5, \(phase.title)"))
        .accessibilityHint(Text("Opens all steps."))
        .accessibilityIdentifier("journey.rail.compact")
    }
}

private struct JourneyProgressMenu: View {
    let phase: SessionPhase
    let reached: Set<SessionPhase>
    var onSelect: (SessionPhase) -> Void
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var activePaper

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                menuHeader
                VStack(spacing: 5) {
                    ForEach(SessionPhase.allCases) { item in
                        phaseRow(item)
                    }
                }
                Text("Return to any visited step.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 360, maxWidth: 380)
        .frame(idealHeight: 570, maxHeight: 620)
        .background(Palette.surface)
        .animation(reduceMotion ? nil : .stopMotion(duration: 0.32, fps: 15), value: phase)
        .accessibilityIdentifier("journey.menu")
    }

    private var menuHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THE LEARNING PROCESS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(JourneyPressStyle())
                .accessibilityLabel(Text("Close journey"))
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your journey.")
                        .font(TypeScale.display(29))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("One idea at a time.")
                        .font(TypeScale.hand(13))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("journey_collage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 92)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 7)
            .padding(.bottom, 9)
            Rectangle().fill(Palette.hairline).frame(height: 0.75)
                .padding(.horizontal, 7)
        }
    }

    private func phaseRow(_ item: SessionPhase) -> some View {
        let current = item == phase
        let visited = reached.contains(item)
        let available = current || visited

        return Button { onSelect(item) } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(item.journeyNumber)
                        .font(.system(size: 27, weight: current ? .bold : .regular).width(.condensed))
                        .monospacedDigit()
                    if current {
                        Text("NOW")
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(1.1)
                    }
                }
                .frame(width: 37)
                .foregroundStyle(available ? Palette.ink : Palette.ink3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(TypeScale.heading(17))
                        .foregroundStyle(available ? Palette.ink : Palette.ink2)
                    Text(item.subtitle)
                        .font(.system(.caption))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if current {
                        JourneyPencilIcon(phase: item).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: visited ? "arrow.uturn.backward" : "lock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.ink2)
                    }
                }
                .frame(width: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 66)
            .background {
                if current {
                    JourneyPaperShape()
                        .fill(Palette.highlighter)
                        .matchedGeometryEffect(id: "current-phase", in: activePaper)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(visited ? Palette.canvas.opacity(0.55) : Color.clear)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(JourneyPressStyle())
        .disabled(!available)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(item.rawValue + 1), \(item.title)"))
        .accessibilityValue(Text(current ? "Current step" : visited ? "Visited" : "Not yet available"))
        .accessibilityHint(Text(available ? item.subtitle : String(localized: "Continue through the earlier steps to unlock.")))
        .accessibilityAddTraits(current ? [.isSelected] : [])
        .accessibilityIdentifier("journey.phase.\(item.rawValue)")
    }
}

private struct JourneyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Small clipped corners give the highlight a cut-paper edge without a noisy shader.
nonisolated private struct JourneyPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut: CGFloat = min(5, rect.height * 0.1)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

nonisolated private struct JourneyPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

private extension SessionPhase {
    var journeyNumber: String { String(format: "%02d", rawValue + 1) }
    var journeySymbol: String { self == .details ? "brain" : symbol }
    var journeyPencilAsset: String {
        switch self {
        case .collect: "journey_collect_pencil"
        case .sort: "journey_sort_pencil"
        case .backbone: "journey_backbone_pencil"
        case .check: "journey_reflect_pencil"
        case .details: "journey_mindmap_pencil"
        }
    }
}

#Preview("Journey — Reflect") {
    VStack(spacing: 20) {
        JourneyProgressControl(phase: .check, reached: [.collect, .sort, .backbone, .check], isExpanded: .constant(false))
        JourneyProgressMenu(phase: .check, reached: [.collect, .sort, .backbone, .check], onSelect: { _ in }, onClose: {})
    }
    .padding(24)
    .background(Palette.canvas)
}
