import SwiftUI

/// Floating glass toolbar at the bottom of the canvas.
struct CanvasToolbar: View {
    @Bindable var model: SessionModel
    var onFit: () -> Void
    var onAdd: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    drawingTools
                    editingTools
                    reviewButton()
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        drawingTools
                        reviewButton()
                    }
                    editingTools
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        drawingTools
                        reviewButton(compact: true)
                    }
                    editingTools
                }
            }
        }
    }

    private var drawingTools: some View {
        HStack(spacing: 4) {
            tool("plus", String(localized: "Add idea"), action: onAdd)
                .keyboardShortcut("n", modifiers: .command)
            penTool(.handwrite, symbol: "pencil.and.scribble", label: String(localized: "Handwrite ideas"))
                .disabled(!PenMode.handwritingAvailable)
            penTool(.sketch, symbol: "scribble.variable", label: String(localized: "Sketch"))
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
    }

    private var editingTools: some View {
        HStack(spacing: 4) {
            tool("arrow.uturn.backward", String(localized: "Undo")) { withAnimation(Motion.flow) { model.undo() } }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            tool("arrow.uturn.forward", String(localized: "Redo")) { withAnimation(Motion.flow) { model.redo() } }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            tool("wand.and.rays", String(localized: "Tidy up")) { withAnimation(Motion.flow) { model.tidy() } }
                .disabled(model.map.nodes.count < 2)
            tool("arrow.up.left.and.down.right.magnifyingglass", String(localized: "Fit map"), action: onFit)
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
    }

    private func reviewButton(compact: Bool = false) -> some View {
        SessionFlowControls(model: model, compact: compact, onOpenMap: model.openMindMap)
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .accessibilityLabel(Text(label))
        .help(label)
    }

    private func penTool(_ mode: PenMode, symbol: String, label: String) -> some View {
        let active = model.penMode == mode
        return Button {
            withAnimation(Motion.snappy) { model.penMode = active ? .off : mode }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(active ? Palette.surface : Palette.ink)
                .background(Circle().fill(active ? Palette.ink : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(label)
    }
}

/// Edits one link: direction and its one-sentence explanation.
struct EdgeInspector: View {
    @Bindable var model: SessionModel
    var edge: MapEdge
    var from: MapNode
    var to: MapNode
    var width: CGFloat = 380
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW ARE THEY RELATED?")
                .font(TypeScale.overline(11))
                .foregroundStyle(Palette.oliveDeep)
            VStack(spacing: 6) {
                direction("\(short(from.label)) → \(short(to.label))", active: edge.isDirected) { model.setDirection(.forward, for: edge.id) }
                direction(String(localized: "No direction"), active: !edge.isDirected) { model.setDirection(.none, for: edge.id) }
                direction("\(short(to.label)) → \(short(from.label))", active: false) { model.setDirection(.backward, for: edge.id) }
            }
            TextField(String(localized: "Explain it in one sentence…"), text: $reason, axis: .vertical)
                .font(TypeScale.hand(16))
                .lineLimit(1...3)
                .padding(10)
                .background(Palette.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onSubmit(save)
            HStack {
                Button(role: .destructive) {
                    withAnimation(Motion.snappy) { model.deleteEdge(edge.id) }
                } label: {
                    Label(String(localized: "Delete link"), systemImage: "trash")
                }
                .buttonStyle(.glass)
                Spacer()
                Button(String(localized: "Done")) {
                    save()
                    withAnimation(Motion.snappy) { model.selection = .none }
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.ink)
            }
        }
        .padding(16)
        .frame(width: width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { reason = edge.reason }
        .onChange(of: edge.id) { _, _ in reason = edge.reason }
    }

    private func short(_ label: String) -> String {
        label.count > 14 ? String(label.prefix(13)) + "…" : label
    }

    private func direction(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.snappy, action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .foregroundStyle(active ? Palette.surface : Palette.ink)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Palette.ink : Palette.surface.opacity(0.7)))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != edge.reason { model.setReason(trimmed, for: edge.id) }
    }
}
