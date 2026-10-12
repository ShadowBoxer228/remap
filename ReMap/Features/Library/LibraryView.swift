import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [UUID] = []
    @State private var showNewSession = false
    @State private var showSettings = false
    @State private var renaming: StudySession?
    @State private var renameText = ""
    @State private var covers = CoverStore()
    @AppStorage("onboardingDone") private var onboardingDone = true
    @AppStorage("automaticTopicCovers") private var coversEnabled = true
    @AppStorage("cloudCoachEnabled") private var coachEnabled = true

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                let inset: CGFloat = geometry.size.width < 600 ? 22 : 40
                let available = max(1, geometry.size.width - inset * 2)
                let count = LibraryPaperStyle.columnCount(width: available,
                                                          isPortrait: geometry.size.width < geometry.size.height)
                let width = (available - CGFloat(count - 1) * 28) / CGFloat(count)
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        header
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: count),
                                  alignment: .leading, spacing: 28) {
                            NewSessionCard(width: width) { showNewSession = true }
                                .modifier(LibraryEntrance(index: 0))
                            ForEach(Array(app.store.sortedSessions.enumerated()), id: \.element.id) { index, session in
                                Button { path.append(session.id) } label: {
                                    SessionCard(session: session, width: width, image: covers.image(for: session.id),
                                                isWorking: covers.isWorking(session.id))
                                }
                                .buttonStyle(LibraryPressStyle())
                                .contextMenu { menu(for: session) }
                                .accessibilityIdentifier("library.topic.\(session.id)")
                                .accessibilityLabel("\(session.title), \(session.phase.title)")
                                .modifier(LibraryEntrance(index: index + 1))
                            }
                            if app.store.sessions.isEmpty {
                                Button { path.append(app.createDemoSession()) } label: {
                                    demoCard(width: width)
                                }
                                .buttonStyle(LibraryPressStyle())
                                .accessibilityIdentifier("library.demo")
                                .modifier(LibraryEntrance(index: 1))
                            }
                        }
                        .padding(.bottom, 36)
                    }
                    .padding(.horizontal, inset)
                    .padding(.top, 24)
                }
                .scrollIndicators(.hidden)
                .background(LibraryBackdrop())
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                SessionView(sessionID: id).toolbar(.hidden, for: .navigationBar)
            }
            .sheet(isPresented: $showNewSession) {
                NewSessionSheet { id in
                    showNewSession = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        path.append(id)
                    }
                }
            }
            .sheet(isPresented: $showSettings) { LibrarySettingsView() }
            .alert(String(localized: "Rename map"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(String(localized: "Title"), text: $renameText)
                Button(String(localized: "Cancel"), role: .cancel) { renaming = nil }
                Button(String(localized: "Save")) {
                    // Re-read the current session, preserving edits made while the alert was open.
                    if let original = renaming, var s = app.store.session(original.id),
                       !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        s.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if s.map.title == original.title { s.map.title = s.title }
                        app.store.update(s)
                    }
                    renaming = nil
                }
            }
            .onAppear {
                InternalConnectionBootstrap.configureIfAvailable()
                synchronizeCovers()
            }
            .task(id: coachEnabled && scenePhase == .active) {
                guard coachEnabled, scenePhase == .active else { return }
                await CoachEnrollment.shared.warmUp()
                guard !Task.isCancelled else { return }
                synchronizeCovers()
            }
            .onChange(of: app.store.sessions.map(\.id)) { _, _ in synchronizeCovers() }
            .onChange(of: coversEnabled) { _, _ in synchronizeCovers() }
            .onChange(of: showSettings) { _, visible in
                if !visible { synchronizeCovers() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { synchronizeCovers() }
                if phase == .background { covers.pause() }
            }
        }
    }

    private func synchronizeCovers() {
        covers.synchronize(app.store.sortedSessions, enabled: coversEnabled)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(verbatim: "ReMap")
                .font(TypeScale.display(36))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
                Button("New demo session", systemImage: "sparkles") { path.append(app.createDemoSession()) }
                Button("Replay onboarding", systemImage: "book") { onboardingDone = false }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 44)
                    .background(LibraryPaperShape(seed: 12).fill(Palette.surface.opacity(0.88)))
            }
            .accessibilityLabel("Library menu")
            .accessibilityIdentifier("library.menu")
        }
    }

    private func demoCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TopicCoverView(image: nil, seed: 11, width: max(1, width - 24), symbol: "leaf")
                .padding(12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Try an example").font(TypeScale.heading(22)).foregroundStyle(Palette.ink)
                Text("Endocrine basics").font(TypeScale.hand(16)).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(.horizontal, 22).padding(.bottom, 18)
        }
        .background(LibraryPaperSurface(seed: 11))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func menu(for session: StudySession) -> some View {
        Button(String(localized: "Rename"), systemImage: "pencil") {
            renameText = session.title
            renaming = session
        }
        let state = covers.records[session.id]?.state
        Button(state == .uncertain ? "Check cover" :
                ([.failed, .waiting, .limited].contains(state) ? "Retry cover" : "Refresh cover"),
               systemImage: "arrow.clockwise") { covers.refresh(session) }
            .disabled(!coversEnabled || covers.isWorking(session.id))
        Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) {
            covers.remove(session.id)
            withAnimation(reduceMotion ? nil : Motion.snappy) { app.store.delete(session.id) }
        }
    }
}

struct NewSessionCard: View {
    var width: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    // Deliberately identical to the original plus and moving aura.
                    GrainBlob(color: Palette.olive, seed: 3).frame(width: 96, height: 84)
                    Image(systemName: "plus").font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.ink)
                }
                .frame(height: max(1, width - 24) * 0.75)
                .frame(maxWidth: .infinity)
                .padding(12)
                Text("New map")
                    .font(TypeScale.heading(22)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
                    .padding(.horizontal, 22).padding(.bottom, 18)
            }
            .background(LibraryPaperSurface(seed: 3, color: Palette.surface.opacity(0.88)))
            .contentShape(Rectangle())
        }
        .buttonStyle(LibraryPressStyle())
        .accessibilityIdentifier("library.new-map")
    }
}

struct SessionCard: View {
    var session: StudySession
    var width: CGFloat
    var image: UIImage? = nil
    var isWorking = false

    private var seed: Double { LibraryPaperStyle.seed(session.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopicCoverView(image: image, seed: seed, width: max(1, width - 24), isWorking: isWorking,
                           symbol: session.source.kind == .youtube ? "play.rectangle" : "book.closed")
                .clipShape(LibraryPaperShape(seed: seed + 3))
                .padding(12)
            VStack(alignment: .leading, spacing: 12) {
                Text(session.title)
                    .font(TypeScale.heading(22))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                PhaseDots(phase: session.phase)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .padding(.horizontal, 22).padding(.bottom, 18)
        }
        .background(LibraryPaperSurface(seed: seed))
        .rotationEffect(.degrees((seed.truncatingRemainder(dividingBy: 201) - 100) / 100))
        .contentShape(Rectangle())
    }
}

/// Compact session progress: one linked circle per phase.
struct PhaseDots: View {
    var phase: SessionPhase

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionPhase.allCases) { p in
                if p != .collect {
                    Rectangle().fill(p <= phase ? Palette.ink : Palette.ink3.opacity(0.5)).frame(width: 10, height: 1.5)
                }
                Circle()
                    .strokeBorder(p <= phase ? Palette.ink : Palette.ink3.opacity(0.6), lineWidth: 1.5)
                    .background(Circle().fill(p < phase ? Palette.ink : (p == phase ? Palette.olive : .clear)).padding(2.5))
                    .frame(width: 13, height: 13)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Phase: \(phase.title)"))
    }
}

/// A thumbnail of the map, fitted into the card.
struct MiniMapView: View {
    var map: MindMap

    var body: some View {
        Canvas { ctx, size in
            guard !map.nodes.isEmpty else {
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for (i, dx) in [-60.0, 0, 60].enumerated() {
                    let r: CGFloat = i == 1 ? 14 : 9
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x + dx - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(Palette.ink3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                return
            }
            let b = map.bounds.insetBy(dx: -90, dy: -50)
            let k = min(size.width / max(b.width, 1), size.height / max(b.height, 1))
            let ox = (size.width - b.width * k) / 2, oy = (size.height - b.height * k) / 2
            func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: (pt.x - b.minX) * k + ox, y: (pt.y - b.minY) * k + oy) }
            for e in map.edges {
                guard let a = map.node(e.from), let z = map.node(e.to) else { continue }
                var path = Path(); path.move(to: p(a.position)); path.addLine(to: p(z.position))
                ctx.stroke(path, with: .color(Palette.ink.opacity(0.7)), lineWidth: 1.2)
            }
            for n in map.nodes {
                let r: CGFloat = n.isBackbone ? 9 : 6
                let c = p(n.position)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(n.group.map { Palette.branch($0) } ?? (n.isBackbone ? Palette.oliveDeep : Palette.olive)))
            }
        }
    }
}
