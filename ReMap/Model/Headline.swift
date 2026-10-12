import Foundation

/// Where a headline belongs in the map's hierarchy — the user's own judgment during priming.
nonisolated enum HeadlineRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case backbone, topic, detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backbone: String(localized: "Backbone")
        case .topic: String(localized: "Topic")
        case .detail: String(localized: "Detail")
        }
    }

    var hint: String {
        switch self {
        case .backbone: String(localized: "The few ideas that carry the whole topic.")
        case .topic: String(localized: "Ideas that hang on the backbone.")
        case .detail: String(localized: "Facts you attach later — or turn into flashcards.")
        }
    }

    var symbol: String {
        switch self {
        case .backbone: "point.3.connected.trianglepath.dotted"
        case .topic: "circle.hexagongrid"
        case .detail: "text.alignleft"
        }
    }
}

/// A headline collected from the source during priming.
nonisolated struct Headline: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var page: Int? = nil
    var level: Int = 0
    var role: HeadlineRole? = nil
    /// Pure memorization details don't belong on the map — they become flashcards.
    var isFlashcard = false
}
