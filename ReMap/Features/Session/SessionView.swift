import SwiftUI

struct SessionView: View {
    var sessionID: UUID
    @Environment(AppModel.self) private var app
    @State private var model: SessionModel?

    var body: some View {
        Group {
            if let model {
                SessionScreen(model: model)
            } else {
                Palette.canvas.ignoresSafeArea()
            }
        }
        .task(id: sessionID) {
            guard model == nil, let session = app.store.session(sessionID) else { return }
            model = SessionModel(session: session, store: app.store, ingestor: app.ingestor)
        }
    }
}

private struct SessionScreen: View {
    @Bindable var model: SessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerHeight: CGFloat = 52

    var body: some View {
        ZStack {
            if model.session.phase.usesCanvas {
                CanvasScreen(model: model, onBack: { dismiss() })
            } else {
                VStack(spacing: 0) {
                    SessionHeader(model: model, onBack: { dismiss() })
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    GeometryReader { workspace in
                        HStack(alignment: .top, spacing: 16) {
                            if model.conversation.presentation == .voice {
                                CoachDock(model: model, width: workspace.size.width < 700 ? 176 : 220,
                                          maxHeight: min(300, max(160, workspace.size.height)))
                                    .padding(.leading, 20)
                            }
                            content
                                .id(model.session.phase.rawValue)
                                .transition(.asymmetric(insertion: .offset(x: 60).combined(with: .opacity),
                                                        removal: .offset(x: -60).combined(with: .opacity)))
                        }
                    }
                }
            }
        }
        .background(PaperBackground())
        .animation(reduceMotion ? nil : .stopMotion(duration: 0.45, fps: 12), value: model.session.phase)
        .overlay {
            if !model.session.phase.usesCanvas && model.conversation.presentation == .chat {
                GeometryReader { geometry in
                    let compact = geometry.size.width < 700
                    let available = max(160, geometry.size.height - headerHeight - 44)
                    CoachDock(model: model,
                              width: compact ? max(1, geometry.size.width - 40) : 340,
                              maxHeight: compact ? min(available, geometry.size.height * 0.4) : min(480, available))
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: compact ? .bottom : .topTrailing)
                        .padding(.horizontal, 20)
                        .padding(.top, headerHeight + 24)
                        .padding(.bottom, 12)
                }
            }
        }
        .overlay {
            CelebrationView(trigger: model.celebrate)
        }
        .onChange(of: scenePhase) { _, phase in
            // Mic permission and Control Center may temporarily make this inactive.
            if phase == .background && model.conversation.presentation == .voice {
                model.conversation.sceneBecameInactive()
            }
        }
        .onDisappear { model.conversation.close() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.session.phase {
        case .collect: CollectView(model: model)
        case .sort: SortView(model: model)
        case .backbone, .check, .details: EmptyView()
        }
    }
}

/// Adaptive session header with a single, recognizable coach entry point.
struct SessionHeader: View {
    @Bindable var model: SessionModel
    var onBack: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                wideHeader
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        backButton
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        coachButton
                        demoMenu
                    }
                    SessionJourneyProgressBar(model: model)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var wideHeader: some View {
        HStack(spacing: 12) {
            backButton
            title
                .frame(width: 272)
            Spacer(minLength: 8)
            SessionJourneyProgressBar(model: model)
                .frame(width: 420)
            Spacer(minLength: 8)
            coachButton
            demoMenu
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text("Back to library"))
    }

    @ViewBuilder private var coachButton: some View {
        if model.conversation.presentation != .voice {
            CoachLauncher(state: CoachCharacterState(model.conversation.activity),
                          isExpanded: model.conversation.presentation != .collapsed) {
                model.conversation.openChat()
            }
        }
    }

    private var title: some View {
        SessionPencilTitle(title: model.session.title, onRename: model.rename)
    }

    private var demoMenu: some View {
        Menu {
            Section(String(localized: "Demo controls")) {
                Button(String(localized: "Auto-sort headlines"), systemImage: "square.stack.3d.up") { model.demoAutoSort() }
                Button(String(localized: "Load the 'wrong' map"), systemImage: "exclamationmark.triangle") {
                    withAnimation(Motion.flow) { model.demoLoadWrongMap() }
                }
                Button(String(localized: "Regroup by function"), systemImage: "arrow.triangle.branch") {
                    withAnimation(Motion.flow) { model.demoRegroup() }
                }
                Menu(String(localized: "Jump to phase")) {
                    ForEach(SessionPhase.allCases) { phase in
                        Button(phase.title) { model.advance(to: phase) }
                    }
                }
                Button(String(localized: "Reset session"), systemImage: "arrow.counterclockwise", role: .destructive) {
                    withAnimation(Motion.flow) { model.demoReset() }
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.headline)
        }
        .buttonStyle(CoachControlStyle(tone: .paper))
        .accessibilityLabel(Text("More"))
    }
}

/// Collect → Sort → Backbone → Reflect → Details, drawn as linked circles.
struct PhaseStepper: View {
    @Bindable var model: SessionModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionPhase.allCases) { phase in
                if phase != .collect {
                    Rectangle()
                        .fill(phase <= model.session.phase ? Palette.ink : Palette.ink3.opacity(0.4))
                        .frame(width: 18, height: 1.5)
                }
                let reached = model.session.reachedPhases[phase] != nil
                let current = phase == model.session.phase
                Button {
                    guard reached else { return }
                    model.advance(to: phase)
                } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().strokeBorder(reached ? Palette.ink : Palette.ink3.opacity(0.5), lineWidth: 1.5)
                            if current {
                                Circle().fill(Palette.ink).padding(3.5)
                            } else if reached {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Palette.ink)
                            }
                        }
                        .frame(width: 18, height: 18)
                        if current {
                            Text(phase.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, current ? 4 : 0)
                }
                .buttonStyle(.plain)
                .disabled(!reached)
                .accessibilityLabel(Text("\(phase.title)\(current ? ", current" : "")"))
            }
        }
        .animation(Motion.snappy, value: model.session.phase)
    }
}
