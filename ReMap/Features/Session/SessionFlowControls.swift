import SwiftUI

/// A visible next step on the board, independent of the coach's chat history.
struct SessionFlowControls: View {
    @Bindable var model: SessionModel
    var compact = false
    var onOpenMap: () -> Void

    private var isReflecting: Bool { model.session.phase == .check }
    private var isMap: Bool { model.session.phase == .details }
    private var findings: [Finding] { MapRules.findings(for: model.map) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: continueFlow) {
                Label(title, systemImage: isReflecting ? "arrow.right" : "questionmark.bubble")
                    .font(.headline)
                    .fixedSize()
                    .padding(.horizontal, compact ? 6 : 10)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.ink)
            .disabled(model.map.nodes.isEmpty)
            .accessibilityIdentifier("session.flow.next")
            .accessibilityHint(Text(hint))

            if model.map.nodes.isEmpty {
                status(String(localized: "Add an idea to continue"))
            } else if isReflecting || isMap {
                if !findings.isEmpty {
                    status(String(localized: "\(findings.count) questions to revisit"))
                } else if isMap {
                    status(String(localized: "Keep editing or add details"))
                } else {
                    status(String(localized: "Continue to your editable map"))
                }
            }
        }
    }

    private var title: String {
        if isReflecting { return String(localized: "Open mind map") }
        if isMap { return String(localized: "Review map") }
        return String(localized: "Reflect on map")
    }

    private var hint: String {
        if isReflecting {
            return String(localized: "Open your interactive map and make the detail ideas available.")
        }
        return String(localized: "Review your map with the coach, one question at a time.")
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 210, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func continueFlow() {
        if isReflecting {
            onOpenMap()
        } else {
            model.reviewMap()
        }
    }
}
