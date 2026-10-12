import Foundation

/// Priming and reflection lead to an editable map that can grow over later sittings.
nonisolated enum SessionPhase: Int, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    // Keep `details` at raw value 4 so existing saved maps reopen in the final workspace.
    case collect, sort, backbone, check, details

    var id: Int { rawValue }
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .collect: String(localized: "Collect")
        case .sort: String(localized: "Sort")
        case .backbone: String(localized: "Backbone")
        case .check: String(localized: "Reflect")
        case .details: String(localized: "Mind map")
        }
    }

    var subtitle: String {
        switch self {
        case .collect: String(localized: "Gather the headlines")
        case .sort: String(localized: "Judge what matters")
        case .backbone: String(localized: "Draw the skeleton")
        case .check: String(localized: "Question your map")
        case .details: String(localized: "Explore, edit and add details")
        }
    }

    var symbol: String {
        switch self {
        case .collect: "tray.and.arrow.down"
        case .sort: "square.stack.3d.up"
        case .backbone: "point.3.connected.trianglepath.dotted"
        case .check: "questionmark.bubble"
        case .details: "point.3.connected.trianglepath.dotted"
        }
    }

    /// Phases that share the canvas.
    var usesCanvas: Bool { self >= .backbone }
}

nonisolated enum SourceKind: String, Codable, Sendable {
    case pdf, text, youtube, demo

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .text: "text.quote"
        case .youtube: "play.rectangle"
        case .demo: "sparkles"
        }
    }
}

nonisolated struct SourceInfo: Codable, Equatable, Sendable {
    var kind: SourceKind
    var name: String
    /// File copied into the app's documents (PDFs).
    var fileName: String? = nil
    var url: URL? = nil
    /// Pasted text or transcript.
    var text: String? = nil
}

nonisolated struct StudySession: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var source: SourceInfo
    var createdAt = Date()
    var updatedAt = Date()
    var phase: SessionPhase = .collect
    /// When each phase was first reached — drives the session timeline.
    var reachedPhases: [SessionPhase: Date] = [.collect: Date()]
    var headlines: [Headline] = []
    var map: MindMap
    var isDemo = false
    /// Number of sittings — the map is meant to grow across several.
    var sittings = 1

    var flashcards: [Headline] { headlines.filter(\.isFlashcard) }

    func headlines(for role: HeadlineRole) -> [Headline] {
        headlines.filter { $0.role == role && !$0.isFlashcard }
    }

    /// Collected headlines not yet drawn on the map.
    var unplacedHeadlines: [Headline] {
        let placed = Set(map.nodes.compactMap(\.headlineID))
        let roles: Set<HeadlineRole> = phase >= .details ? [.backbone, .topic, .detail] : [.backbone, .topic]
        return headlines.filter { h in
            !placed.contains(h.id) && !h.isFlashcard && h.text != map.title && (h.role.map(roles.contains) ?? false)
        }
    }

    var progress: Double {
        let base = Double(phase.rawValue) / Double(SessionPhase.allCases.count - 1)
        return min(1, base)
    }
}
