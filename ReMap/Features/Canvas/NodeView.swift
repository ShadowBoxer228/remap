import SwiftUI

/// A node on the map: a paper tab with a hand-lettered label.
struct NodeView: View {
    var node: MapNode
    @Bindable var model: SessionModel
    var onConnectDrag: (CGPoint?) -> Void
    var onConnectEnd: (CGPoint) -> Void
    @State private var dragStart: CGPoint?
    @State private var editText = ""
    @FocusState private var editing: Bool

    private var isSelected: Bool { model.selection.nodeID == node.id }
    private var isFocused: Bool { model.focus.contains(node.id) }
    private var isEditing: Bool { model.editingNodeID == node.id }
    private var groupColor: Color? { node.group.map { Palette.branch($0) } }
    private var isGroupingTarget: Bool { model.coach.groupingCandidates.contains(node.id) }

    var body: some View {
        label
            .padding(.horizontal, node.isBackbone ? 20 : 16)
            .padding(.trailing, isSelected && !isEditing ? 36 : 0)
            .frame(minHeight: node.isBackbone ? 58 : 48)
            .background(background)
            .overlay(selectionRing)
            .overlay(alignment: .topTrailing) { glyph }
            .overlay(alignment: .trailing) { if isSelected && !isEditing { connectHandle } }
            .background { if isFocused { highlighterBlob } }
            .pulse(on: isFocused ? model.focusToken : -1)
            .scaleEffect(dragStart == nil ? 1 : 1.06)
            .shadow(color: .black.opacity(dragStart == nil ? 0 : 0.18), radius: 14, y: 8)
            .animation(Motion.snappy, value: dragStart == nil)
            .opacity(model.ghosts.isEmpty || model.placingNodeID == node.id ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .gesture(dragGesture)
            .onTapGesture(perform: tap)
            .contextMenu { contextMenu }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(node.label))
            .accessibilityValue(Text(node.isBackbone ? "Backbone, \(model.map.degree(of: node.id)) links" : "\(model.map.degree(of: node.id)) links"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var label: some View {
        if isEditing {
            TextField("", text: $editText, axis: .horizontal)
                .font(TypeScale.node(backbone: node.isBackbone))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .focused($editing)
                .fixedSize()
                .frame(minWidth: 80)
                .onAppear { editText = node.label; editing = true }
                .onSubmit(commitEdit)
                .onChange(of: editing) { _, now in if !now { commitEdit() } }
        } else {
            Text(node.label)
                .font(TypeScale.node(backbone: node.isBackbone))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: node.isBackbone ? 20 : 16, style: .continuous)
        return shape
            .fill(Palette.surface)
            .overlay(shape.fill((groupColor ?? (node.isBackbone ? Palette.olive : .clear)).opacity(node.isBackbone ? 0.22 : 0.14)))
            .overlay(shape.strokeBorder(groupColor ?? Palette.ink, lineWidth: node.isBackbone ? 2.6 : 1.4))
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.07), radius: 10, y: 5)
    }

    @ViewBuilder
    private var selectionRing: some View {
        if isSelected || isGroupingTarget {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isGroupingTarget ? Palette.oliveDeep : Palette.ink,
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(-7)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if let g = Palette.glyph(node.group) {
            Image(systemName: g)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.branch(node.group))
                .padding(5)
                .background(Circle().fill(Palette.surface))
                .offset(x: 6, y: -6)
        } else if node.isBackbone {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.oliveDeep)
                .padding(5)
                .background(Circle().fill(Palette.surface))
                .offset(x: 6, y: -6)
        }
    }

    private var highlighterBlob: some View {
        GrainBlob(color: Palette.highlighter, seed: Double(node.id.uuid.2), wobble: 0.1)
            .padding(-22)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    /// Drag from here to another node to link them.
    private var connectHandle: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Palette.surface)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Palette.ink))
            .padding(.trailing, 6)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("world"))
                    .onChanged { onConnectDrag($0.location) }
                    .onEnded { onConnectEnd($0.location) }
            )
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(Text("Drag to link"))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("world"))
            .onChanged { value in
                guard !isEditing else { return }
                if dragStart == nil {
                    dragStart = node.position
                    model.beginMove()
                    model.selection = .node(node.id)
                }
                if let start = dragStart {
                    model.moveNode(node.id, to: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
                }
            }
            .onEnded { _ in
                dragStart = nil
                model.endMove()
            }
    }

    private func tap() {
        if model.coach.groupingCandidates.contains(node.id) {
            withAnimation(Motion.flow) { model.coach.assignToGroup(node.id) }
            return
        }
        if isSelected {
            model.editingNodeID = node.id
        } else {
            withAnimation(Motion.snappy) {
                model.selection = .node(node.id)
                model.editingNodeID = nil
            }
        }
    }

    private func commitEdit() {
        guard model.editingNodeID == node.id else { return }
        model.editingNodeID = nil
        withAnimation(Motion.snappy) { model.renameNode(node.id, to: editText) }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(String(localized: "Edit label"), systemImage: "pencil") {
            model.selection = .node(node.id)
            model.editingNodeID = node.id
        }
        Button(node.isBackbone ? String(localized: "Remove from backbone") : String(localized: "Mark as backbone"),
               systemImage: node.isBackbone ? "star.slash" : "star") {
            withAnimation(Motion.snappy) { model.toggleBackbone(node.id) }
        }
        Menu(String(localized: "Group color"), systemImage: "paintpalette") {
            ForEach(0..<Palette.branches.count, id: \.self) { i in
                Button {
                    withAnimation(Motion.snappy) { model.setGroup(i, for: node.id) }
                } label: {
                    Label(String(localized: "Group \(i + 1)"), systemImage: Palette.branchGlyphs[i])
                }
            }
            Button(String(localized: "No group"), systemImage: "circle.slash") {
                withAnimation(Motion.snappy) { model.setGroup(nil, for: node.id) }
            }
        }
        Button(String(localized: "Where should this go?"), systemImage: "questionmark.circle") {
            withAnimation(Motion.flow) { model.startPlacement(label: node.label, nodeID: node.id) }
        }
        Divider()
        Menu(String(localized: "Connect to"), systemImage: "arrow.right") {
            ForEach(model.map.nodes.filter { $0.id != node.id }) { other in
                Button(other.label) {
                    if let id = model.connect(node.id, other.id) { model.selection = .edge(id) }
                }
            }
        }
        Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) {
            withAnimation(Motion.snappy) { model.deleteNode(node.id) }
        }
    }
}

/// A suggested home for a node: dashed "marching ants" outline with the label inside.
struct GhostNodeView: View {
    var label: String
    var parentLabel: String
    var index: Int
    var isChosen: Bool
    var onTap: () -> Void
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(TypeScale.node(backbone: false))
                .foregroundStyle(Palette.ink.opacity(isChosen ? 1 : 0.6))
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isChosen ? Palette.butter : Palette.surface.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.ink, style: StrokeStyle(lineWidth: 1.6, dash: [6, 5], dashPhase: phase))
                )
            Text("\(index + 1) · near \(parentLabel)")
                .font(TypeScale.hand(13, weight: 600))
                .foregroundStyle(Palette.oliveDeep)
        }
        .scaleEffect(isChosen ? 1.08 : 1)
        .animation(Motion.spawn, value: isChosen)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            if !reduceMotion { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { phase = -22 } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Option \(index + 1): next to \(parentLabel)"))
    }
}
