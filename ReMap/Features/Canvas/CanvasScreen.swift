import SwiftUI

/// One continuous viewport, with controls floating above the paper.
struct CanvasScreen: View {
    @Bindable var model: SessionModel
    var onBack: () -> Void
    @State private var nodeSizes: [UUID: CGSize] = [:]
    @State private var panStart: CGSize?
    @State private var pinchLast: CGFloat = 1
    @State private var connectFrom: UUID?
    @State private var connectPoint: CGPoint?
    @State private var visibleRect: CGRect = .zero
    @State private var followsMap = true
    @State private var keyboardIsVisible = false
    @State private var awaitingNodeMeasurements = true
    @State private var previousHasTopics = false
    @State private var previousPanelOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let worldSize = CGSize(width: 4000, height: 3000)

    var body: some View {
        GeometryReader { workspace in
            paper
                .overlay {
                    workspaceControls(size: workspace.size)
                }
                .coordinateSpace(.named("workspace"))
        }
        .onKeyPress(.delete) { deleteSelection() }
        .onKeyPress(.escape) {
            model.selection = .none
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardIsVisible = false
        }
    }

    private func workspaceControls(size: CGSize) -> some View {
        let topicWidth: CGFloat = size.width >= 1000 ? 196 : (size.width >= 700 ? 176 : 148)
        let voice = model.conversation.presentation == .voice
        let voiceWidth: CGFloat = size.width < 700 ? 176 : 220
        let dockWidth: CGFloat = 340
        let leftWidth = max(hasTopics ? topicWidth : 0, voice ? voiceWidth : 0)
        let leadingWidth = leftWidth > 0 ? leftWidth + 16 : 0
        // The borderless figure lives above the topics at the upper left. Text
        // and inspectors use the right dock only when enough paper remains.
        let sideDock = size.width >= 700 && size.width - 40 - leadingWidth - dockWidth - 16 >= 240
        return VStack(spacing: 12) {
            SessionHeader(model: model, onBack: onBack)
            HStack(alignment: .top, spacing: 16) {
                if voice || hasTopics {
                    GeometryReader { left in
                        let voiceHeight = min(size.width < 700 ? 240.0 : 300.0,
                                              max(160, left.size.height - (hasTopics ? 80 : 0)))
                        VStack(alignment: .leading, spacing: 12) {
                            if voice {
                                CoachDock(model: model, width: voiceWidth, maxHeight: voiceHeight)
                                    .frame(height: voiceHeight, alignment: .top)
                            }
                            if hasTopics {
                                CanvasTopicRail(model: model,
                                                maxHeight: max(1, left.size.height - (voice ? voiceHeight + 12 : 0)),
                                                onPlace: placeAtCenter)
                                    .frame(width: topicWidth)
                                    .transition(.opacity.animation(.easeOut(duration: 0.14)))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: leftWidth)
                }
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("workspace")) } action: { rect in
                        updateVisibleRect(rect)
                    }
                if sideDock && (hasInspector || model.conversation.presentation == .chat) {
                    GeometryReader { dock in
                        sidePanel(width: dockWidth, height: dock.size.height, includeVoice: false)
                    }
                    .frame(width: dockWidth)
                }
            }
            .frame(maxHeight: .infinity)
            // Card transitions animate locally; viewport geometry must not drift
            // through intermediate widths while the final topic leaves the rail.
            .animation(nil, value: hasTopics)
            if !sideDock && (hasInspector || model.conversation.presentation == .chat) {
                sidePanel(width: max(1, size.width - 40),
                          height: min(280, size.height * 0.4), includeVoice: false)
            }
            CanvasToolbar(model: model, onFit: {
                followsMap = true
                fit(animated: true)
            }, onAdd: addAtCenter)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(width: size.width, height: size.height)
    }

    private var paper: some View {
        GeometryReader { geo in
            // Overlay keeps the 4000-point world out of the viewport's layout calculation.
            backgroundLayer
                .background { DotGrid(offset: model.camera.offset, scale: model.camera.scale) }
                .overlay(alignment: .topLeading) {
                    world
                        .scaleEffect(model.camera.scale, anchor: .topLeading)
                        .offset(model.camera.offset)
                }
                .overlay {
                    if model.penMode != .off {
                        SketchLayer(model: model)
                            .transition(.opacity)
                    }
                }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .coordinateSpace(.named("canvas"))
            .simultaneousGesture(magnify)
            .gesture(TwoFingerPan { delta in
                followsMap = false
                model.camera.offset.width += delta.width
                model.camera.offset.height += delta.height
            })
            .dropDestination(for: String.self) { items, location in
                drop(items, at: location)
            }
            .onAppear {
                if model.coach.messages.isEmpty { model.coach.greet() }
            }
            .onChange(of: nodeSizes) { _, _ in
                if awaitingNodeMeasurements && model.map.nodes.allSatisfy({ nodeSizes[$0.id] != nil }) {
                    awaitingNodeMeasurements = false
                    if followsMap && !keyboardIsVisible { fit(animated: false) }
                }
            }
            .onChange(of: model.camera.isPlaced) { _, placed in
                if !placed { followsMap = true; placeCamera() }
            }
        }
    }

    // MARK: - Layers

    private var backgroundLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .named("canvas")) { location in
                let world = model.camera.toWorld(location)
                withAnimation(Motion.spawn) {
                    let id = model.addNode(String(localized: "New idea"), at: world, backbone: model.session.phase == .backbone && model.map.nodes.count < 4)
                    model.selection = .node(id)
                    model.editingNodeID = id
                }
            }
            .onTapGesture {
                withAnimation(Motion.snappy) {
                    model.selection = .none
                    model.editingNodeID = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        followsMap = false
                        if panStart == nil { panStart = model.camera.offset }
                        guard let start = panStart else { return }
                        model.camera.offset = CGSize(width: start.width + value.translation.width,
                                                     height: start.height + value.translation.height)
                    }
                    .onEnded { _ in panStart = nil }
            )
    }

    private var world: some View {
        let map = model.map
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Self.worldSize.width, height: Self.worldSize.height)
                .allowsHitTesting(false)
            if model.penMode != .sketch {
                SketchImage(data: model.map.sketch)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 8, paused: reduceMotion)) { context in
                let frame = Int(context.date.timeIntervalSinceReferenceDate * 8) % 100_000
                ZStack(alignment: .topLeading) {
                    ForEach(Array(map.edges.enumerated()), id: \.element.id) { index, edge in
                        if let a = map.node(edge.from), let b = map.node(edge.to) {
                            let ends = endpoints(a, b)
                            EdgeView(edge: edge, start: ends.0, end: ends.1,
                                     isBackbone: a.isBackbone && b.isBackbone,
                                     isSelected: model.selection.edgeID == edge.id,
                                     isFocused: model.focus.contains(edge.id),
                                     focusToken: model.focusToken,
                                     wobbleFrame: frame,
                                     appearDelay: Double(min(index, 12)) * 0.05)
                                .onTapGesture {
                                    withAnimation(Motion.snappy) { model.selection = .edge(edge.id) }
                                }
                                .transition(.opacity)
                        }
                    }
                    ghostLinks(frame: frame)
                    rubberBand(frame: frame)
                }
            }

            ForEach(map.nodes) { node in
                NodeView(node: node, model: model,
                         onConnectDrag: { point in
                             connectFrom = node.id
                             connectPoint = point
                         },
                         onConnectEnd: { point in finishConnect(from: node.id, at: point) })
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { nodeSizes[node.id] = $0 }
                    .position(node.position)
                    .transition(.asymmetric(insertion: entrance(for: node),
                                            removal: reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity)))
                    .onAppear { model.spawnOrigins[node.id] = nil }
            }

            ForEach(Array(model.ghosts.enumerated()), id: \.element.id) { index, ghost in
                GhostNodeView(label: model.placingLabel ?? "",
                              parentLabel: map.node(ghost.parentID)?.label ?? "",
                              index: index,
                              isChosen: model.coach.chosenPlacement?.id == ghost.id) {
                    withAnimation(Motion.spawn) { model.coach.choose(ghost) }
                }
                .fixedSize()
                .position(ghost.position)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: Self.worldSize.width, height: Self.worldSize.height, alignment: .topLeading)
        .coordinateSpace(.named("world"))
        .animation(reduceMotion ? .easeOut(duration: 0.14) : Motion.flow, value: map.nodes.map(\.position))
        .animation(Motion.spawn, value: model.ghosts)
    }

    private func entrance(for node: MapNode) -> AnyTransition {
        if reduceMotion { return .opacity }
        guard let origin = model.spawnOrigins[node.id] else { return .pop }
        return AnyTransition(GrowFromPoint(offset: CGSize(width: origin.x - node.position.x, height: origin.y - node.position.y)))
    }

    @ViewBuilder
    private func ghostLinks(frame: Int) -> some View {
        ForEach(model.ghosts) { ghost in
            if let parent = model.map.node(ghost.parentID) {
                ArrowShape(start: ghost.position, end: EdgeGeometry.clip(center: parent.position, toward: ghost.position, size: size(of: parent)),
                           bend: 0.08, head: true, wobbleSeed: 3, wobbleFrame: frame)
                    .stroke(Palette.ink.opacity(model.coach.chosenPlacement?.id == ghost.id ? 0.8 : 0.3),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 6]))
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func rubberBand(frame: Int) -> some View {
        if let from = connectFrom, let point = connectPoint, let node = model.map.node(from) {
            ArrowShape(start: EdgeGeometry.clip(center: node.position, toward: point, size: size(of: node)), end: point,
                       bend: 0.06, head: true, wobbleSeed: 9, wobbleFrame: frame)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [8, 6]))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Docked panels

    private var hasInspector: Bool { model.selection.edgeID != nil }
    private var hasTopics: Bool { !model.session.unplacedHeadlines.isEmpty }
    private var hasPanel: Bool { hasInspector || model.conversation.presentation != .collapsed }

    @ViewBuilder
    private func sidePanel(width: CGFloat, height: CGFloat, includeVoice: Bool = true) -> some View {
        let showCoach = model.conversation.presentation == .chat || (includeVoice && model.conversation.presentation == .voice)
        let availableCoachHeight = hasInspector ? max(1, (height - 12) * 0.6) : height
        let coachHeight = model.conversation.presentation == .voice ? min(380, availableCoachHeight) : availableCoachHeight
        VStack(spacing: 12) {
            if showCoach {
                CoachDock(model: model, width: width, maxHeight: coachHeight)
            }
            if let edgeID = model.selection.edgeID, let edge = model.map.edges.first(where: { $0.id == edgeID }),
               let a = model.map.node(edge.from), let b = model.map.node(edge.to) {
                ScrollView {
                    EdgeInspector(model: model, edge: edge, from: a, to: b, width: width)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: showCoach ? max(1, height - coachHeight - 12) : height)
            }
        }
    }

    // MARK: - Geometry

    private func size(of node: MapNode) -> CGSize {
        nodeSizes[node.id] ?? NodeMetrics.size(for: node)
    }

    private func endpoints(_ a: MapNode, _ b: MapNode) -> (CGPoint, CGPoint) {
        (EdgeGeometry.clip(center: a.position, toward: b.position, size: size(of: a)),
         EdgeGeometry.clip(center: b.position, toward: a.position, size: size(of: b), padding: 12))
    }

    private func node(at point: CGPoint) -> MapNode? {
        model.map.nodes.last { n in
            let s = size(of: n)
            return CGRect(x: n.position.x - s.width / 2 - 10, y: n.position.y - s.height / 2 - 10,
                          width: s.width + 20, height: s.height + 20).contains(point)
        }
    }

    // MARK: - Actions

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                followsMap = false
                let factor = value.magnification / pinchLast
                pinchLast = value.magnification
                model.camera.zoom(by: factor, anchor: value.startLocation)
            }
            .onEnded { _ in pinchLast = 1 }
    }

    private func finishConnect(from: UUID, at point: CGPoint) {
        defer { connectFrom = nil; connectPoint = nil }
        guard let source = model.map.node(from), point.distance(to: source.position) > 40 else { return }
        if let target = node(at: point), target.id != from {
            withAnimation(Motion.snappy) {
                if let edgeID = model.connect(from, target.id) { model.selection = .edge(edgeID) }
            }
        } else {
            // Dragged into empty paper: grow a new idea there, already linked.
            withAnimation(Motion.spawn) {
                let id = model.addNode(String(localized: "New idea"), at: point, from: source.position)
                model.connect(from, id)
                model.selection = .node(id)
                model.editingNodeID = id
            }
        }
    }

    private func drop(_ items: [String], at location: CGPoint) -> Bool {
        let world = model.camera.toWorld(location)
        var placed = false
        for (i, item) in items.enumerated() {
            guard let id = UUID(uuidString: item), let headline = model.session.unplacedHeadlines.first(where: { $0.id == id }) else { continue }
            withAnimation(reduceMotion ? .easeOut(duration: 0.14) : Motion.spawn) {
                model.addNode(headline.text, at: CGPoint(x: world.x, y: world.y + CGFloat(i) * 70), headlineID: headline.id)
            }
            placed = true
        }
        return placed
    }

    private func placeAtCenter(_ headline: Headline) {
        guard model.session.unplacedHeadlines.contains(where: { $0.id == headline.id }) else { return }
        let center = model.camera.toWorld(visibleRect.center)
        let jitter = CGPoint(x: CGFloat.random(in: -60...60), y: CGFloat.random(in: -40...40))
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : Motion.spawn) {
            model.addNode(headline.text, at: center + jitter, headlineID: headline.id)
        }
    }

    private func addAtCenter() {
        let center = model.camera.toWorld(visibleRect.center)
        withAnimation(Motion.spawn) {
            let id = model.addNode(String(localized: "New idea"), at: center)
            model.selection = .node(id)
            model.editingNodeID = id
        }
    }

    private func deleteSelection() -> KeyPress.Result {
        guard model.editingNodeID == nil else { return .ignored }
        switch model.selection {
        case .node(let id): withAnimation(Motion.snappy) { model.deleteNode(id) }
        case .edge(let id): withAnimation(Motion.snappy) { model.deleteEdge(id) }
        case .none: return .ignored
        }
        return .handled
    }

    private func updateVisibleRect(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let previous = visibleRect
        let topicsChanged = previousHasTopics != hasTopics
        let controlsChanged = previousPanelOpen != hasPanel
        previousHasTopics = hasTopics
        previousPanelOpen = hasPanel
        visibleRect = rect
        if !model.camera.isPlaced || model.map.nodes.isEmpty {
            placeCamera()
        } else if topicsChanged && !previous.isEmpty {
            // Removing the final topic only uncovers paper. Keep its drop point fixed.
            // Undo can restore the rail without moving the map either.
            return
        } else if followsMap && !keyboardIsVisible && (controlsChanged || abs(rect.width - previous.width) > 1) {
            fit(animated: false)
        } else if !previous.isEmpty {
            // A height-only resize (including software-keyboard transitions) keeps the zoom.
            // Do not depend on keyboard notification ordering relative to SwiftUI layout.
            model.camera.offset.width += rect.midX - previous.midX
            model.camera.offset.height += rect.midY - previous.midY
        }
    }

    private func placeCamera() {
        guard !visibleRect.isEmpty else { return }
        awaitingNodeMeasurements = model.map.nodes.contains { nodeSizes[$0.id] == nil }
        if model.map.nodes.isEmpty {
            model.camera.scale = 0.9
            model.camera.center(on: DemoContent.center, in: visibleRect)
        } else {
            fit(animated: false)
        }
        model.camera.isPlaced = true
    }

    private func fit(animated: Bool) {
        guard !model.map.nodes.isEmpty, !visibleRect.isEmpty else { return }
        // Include the labels themselves, so fitting the map never clips an edge node.
        let bounds = model.map.nodes.reduce(CGRect.null) { bounds, node in
            let nodeSize = self.size(of: node)
            return bounds.union(CGRect(x: node.position.x - nodeSize.width / 2,
                                       y: node.position.y - nodeSize.height / 2,
                                       width: nodeSize.width, height: nodeSize.height))
        }
        let apply = {
            model.camera.fit(bounds, in: visibleRect)
        }
        if animated { withAnimation(Motion.flow, apply) } else { apply() }
    }
}

/// Two-finger pan via UIKit, so it also works on top of the Pencil sketch layer.
struct TwoFingerPan: UIGestureRecognizerRepresentable {
    var onPan: (CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.allowedScrollTypesMask = .all
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard let view = recognizer.view else { return }
        let t = recognizer.translation(in: view)
        recognizer.setTranslation(.zero, in: view)
        onPan(CGSize(width: t.x, height: t.y))
    }
}
