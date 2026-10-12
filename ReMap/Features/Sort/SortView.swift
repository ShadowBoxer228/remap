import SwiftUI

/// Step 2 — a tray of headlines on the left, three generous destinations on the right.
struct SortView: View {
    @Bindable var model: SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var wideLayoutMinimumHeight: CGFloat = 680
    @Namespace private var cards
    @State private var selected: UUID?
    @State private var targeted: SortPile?
    @State private var lastMove: SortMove?
    @State private var coachText = ""
    @State private var coachReplies: [String] = []
    @State private var askedAbout: Set<UUID> = []

    private var unsorted: [Headline] { model.session.headlines.filter { $0.role == nil } }
    private var backboneCount: Int { model.session.headlines(for: .backbone).count }
    private var sortedCount: Int { model.session.headlines.count - unsorted.count }
    private var selectedHeadline: Headline? { model.session.headlines.first { $0.id == selected } }
    private var movement: Animation { reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.46, dampingFraction: 0.84) }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 900 || geometry.size.height < wideLayoutMinimumHeight || typeSize.isAccessibilitySize
            let inset: CGFloat = compact ? 20 : 32
            let width = geometry.size.width - inset * 2
            VStack(alignment: .leading, spacing: 18) {
                if compact {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            heading(compact: true)
                            deck(width: width, compact: true)
                                .frame(height: typeSize.isAccessibilitySize ? 380 : 260)
                            destinations(width: width, compact: true)
                            coachNote
                            footer(compact: true)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        heading(compact: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        coachNote
                            .frame(width: min(680, width * 0.58), alignment: .top)
                    }
                    HStack(alignment: .top, spacing: 22) {
                        let trayWidth = min(380, width * 0.34)
                        deck(width: trayWidth, compact: false)
                            .frame(width: trayWidth)
                        destinations(width: width - trayWidth - 22, compact: false)
                    }
                    .frame(maxHeight: .infinity)
                }
                if !compact { footer(compact: false) }
            }
            .padding(.horizontal, inset)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        // A scoped animation also survives the session store publishing an edit.
        .animation(movement, value: model.session.headlines)
        .animation(reduceMotion ? nil : Motion.snappy, value: selected)
        .animation(reduceMotion ? nil : Motion.snappy, value: targeted)
        .onAppear {
            if coachText.isEmpty {
                coachText = String(localized: "Backbone means the 2–4 ideas everything else hangs on. Most headlines will be topics or details.")
            }
        }
        .onChange(of: model.session.headlines.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected) { self.selected = nil }
        }
    }

    private func heading(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What carries the topic?")
                .font(TypeScale.display(compact ? 34 : 40))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var coachNote: some View {
        CoachNote(text: coachText, replies: coachReplies, onReply: answer)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { if reduceMotion { $0.animation = nil } }
            .accessibilityIdentifier("sort.coach")
    }

    private func destinations(width: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 14) {
            ForEach(HeadlineRole.allCases) { role in
                bucket(role, width: width, compact: compact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
    }

    private func deck(width: CGFloat, compact: Bool) -> some View {
        let isTarget = targeted == .unsorted
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 8)
                countBadge(unsorted.count, tint: Palette.oliveDeep)
                    .accessibilityLabel(Text("\(unsorted.count) unsorted headlines"))
            }
            ScrollView {
                if unsorted.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: 56, height: 56)
                            .background(Palette.olive.opacity(0.16), in: Circle())
                        Text("Room to think.").font(TypeScale.hand(20, weight: 600))
                        Text("You can move any card back here.")
                            .font(TypeScale.hand(15)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .transition(.opacity)
                } else {
                    FlowLayout(spacing: 10) {
                        ForEach(unsorted) { headline in
                            chip(headline, maxWidth: width - 56)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(6)
                }
            }
            .scrollIndicators(.hidden)
            if isTarget {
                Label("Release to return", systemImage: "arrow.uturn.backward")
                    .font(TypeScale.hand(13)).foregroundStyle(Palette.ink2)
                    .transition(.opacity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            SortPaperSurface(targeted: isTarget,
                             available: selectedHeadline?.role != nil, variant: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let headline = selectedHeadline, headline.role != nil { assign(headline.id, to: nil) }
        }
        .dropDestination(for: String.self) { ids, _ in
            move(ids, to: nil)
        } isTargeted: { inside in
            updateTarget(.unsorted, inside: inside)
        }
        .accessibilityIdentifier("sort.unsorted")
    }

    private func bucket(_ role: HeadlineRole, width: CGFloat, compact: Bool) -> some View {
        let items = model.session.headlines.filter { $0.role == role }
        let isTarget = targeted == .role(role)
        let canPlace = selectedHeadline.map { $0.role != role } ?? false
        let tint = Palette.role(role)
        let artSize: CGFloat = typeSize.isAccessibilitySize ? 52 : width < 500 ? 72 : 88
        let inlineArt = width < 430 || typeSize.isAccessibilitySize
        let cardWidth = width - 44 - (inlineArt ? 0 : artSize + 14)
        return HStack(alignment: .top, spacing: 14) {
            if !inlineArt {
                SortRoleArtwork(role: role, size: artSize,
                                arrival: lastMove?.to == role ? lastMove?.token : nil)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if let selected { assign(selected, to: role) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if inlineArt {
                            SortRoleArtwork(role: role, size: artSize,
                                            arrival: lastMove?.to == role ? lastMove?.token : nil)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            SortRoleHeading(role: role, count: items.count,
                                            warning: role == .backbone && items.count > MapRules.maxLinks)
                            Text(role.hint)
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Move selected headline to \(role.title)"))
                .accessibilityValue(Text("\(items.count) ideas"))
                .accessibilityHint(Text(selected == nil ? "Select a headline first." : "Places the selected headline in this section."))
                .accessibilityIdentifier("sort.destination.\(role.rawValue)")

                ScrollViewReader { proxy in
                    ScrollView {
                        FlowLayout(spacing: 10) {
                            ForEach(items) { headline in
                                chip(headline, maxWidth: cardWidth)
                                    .id(headline.id)
                            }
                            if items.isEmpty {
                                HStack(spacing: 8) {
                                    if isTarget || canPlace {
                                        Image(systemName: "arrow.down.left")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(tint)
                                            .accessibilityHidden(true)
                                    }
                                    Text(isTarget ? "Release to place it here" : canPlace ? "Tap here to place your idea" : "Drop an idea here")
                                        .font(TypeScale.hand(15))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(isTarget || canPlace ? Palette.ink : Palette.ink2)
                                .frame(maxWidth: cardWidth, minHeight: 44, alignment: .leading)
                                .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: lastMove?.token) { _, _ in
                        guard let move = lastMove, move.to == role else { return }
                        withAnimation(movement) { proxy.scrollTo(move.id, anchor: .bottom) }
                    }
                }
                .frame(minHeight: typeSize.isAccessibilitySize ? 140 : 50,
                       maxHeight: compact ? (typeSize.isAccessibilitySize ? 240 : 150) : .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: compact ? 170 : 126,
               maxHeight: compact ? nil : .infinity, alignment: .topLeading)
        .background {
            SortPaperSurface(tint: tint, targeted: isTarget, available: canPlace,
                             variant: role == .backbone ? 0 : role == .topic ? 1 : 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let selected { assign(selected, to: role) }
        }
        .dropDestination(for: String.self) { ids, _ in
            move(ids, to: role)
        } isTargeted: { inside in
            updateTarget(.role(role), inside: inside)
        }
        .accessibilityIdentifier("sort.pile.\(role.rawValue)")
    }

    private func chip(_ headline: Headline, maxWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            Button {
                selected = selected == headline.id ? nil : headline.id
            } label: {
                SortHeadlineCard(headline: headline, lifted: selected == headline.id,
                             maxTextWidth: max(40, maxWidth - (headline.role == .detail ? 124 : 76)))
            }
            .buttonStyle(HeadlinePressStyle())
            .accessibilityLabel(Text(headline.text))
            .accessibilityValue(Text(selected == headline.id ? "Selected" : headline.role?.title ?? "Unsorted"))
            .accessibilityAddTraits(selected == headline.id ? .isSelected : [])
            .accessibilityHint(Text("Select, then tap a section. Or drag to move."))
            .accessibilityIdentifier("sort.card.\(headline.text)")
            .accessibilityActions {
                ForEach(HeadlineRole.allCases) { role in
                    Button("Move to \(role.title)") { assign(headline.id, to: role) }
                }
                Button("Return to headlines") { assign(headline.id, to: nil) }
            }
            if headline.role == .detail {
                Button {
                    withAnimation(movement) { model.toggleFlashcard(headline.id) }
                } label: {
                    Image(systemName: headline.isFlashcard ? "rectangle.on.rectangle.angled.fill" : "rectangle.on.rectangle.angled")
                        .font(.system(size: 15))
                        .foregroundStyle(headline.isFlashcard ? Palette.oliveDeep : Palette.ink2)
                        .frame(width: 44, height: 44)
                        .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(HeadlinePressStyle())
                .accessibilityLabel(Text(headline.isFlashcard ? "Keep \(headline.text) on map" : "Make \(headline.text) a flashcard"))
            }
        }
        .matchedGeometryEffect(id: headline.id, in: cards, properties: reduceMotion ? [] : .position)
        .transition(.opacity)
        .draggable(headline.id.uuidString) {
            SortHeadlineCard(headline: headline, lifted: true, maxTextWidth: 280)
                .padding(8)
        }
        .contextMenu {
            ForEach(HeadlineRole.allCases) { role in
                Button("Move to \(role.title)") { assign(headline.id, to: role) }
            }
            if headline.role != nil {
                Button("Return to headlines", systemImage: "arrow.uturn.backward") { assign(headline.id, to: nil) }
            }
        }
        .zIndex(selected == headline.id ? 1 : 0)
    }

    private func countBadge(_ count: Int, tint: Color) -> some View {
        Text("\(count)")
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .contentTransition(.numericText(value: Double(count)))
    }

    private func footer(compact: Bool) -> some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    Text(unsorted.isEmpty ? String(localized: "All sorted. Ready to connect the ideas.") : String(localized: "\(sortedCount) of \(model.session.headlines.count) sorted"))
                        .font(TypeScale.hand(15)).foregroundStyle(Palette.ink2)
                        .contentTransition(.numericText())
                    if let move = lastMove {
                        Button {
                            withAnimation(movement) {
                                model.setRole(move.from, for: move.id)
                                if move.wasFlashcard, move.from == .detail { model.toggleFlashcard(move.id) }
                                coachText = move.coachText
                                coachReplies = move.coachReplies
                                askedAbout = move.askedAbout
                                lastMove = nil
                                selected = nil
                            }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(Palette.oliveDeep)
                        .accessibilityLabel(Text("Undo moving \(move.text)"))
                        .transition(.opacity)
                    }
                }
                ProgressView(value: Double(sortedCount), total: Double(max(model.session.headlines.count, 1)))
                    .tint(Palette.oliveDeep)
                    .frame(maxWidth: 280)
                    .accessibilityLabel(Text("Headlines sorted"))
            }
            if !compact { Spacer(minLength: 0) }
            PrimaryButton(title: String(localized: "Draw the backbone"), systemImage: "arrow.right") {
                model.advance(to: .backbone)
            }
            .disabled(backboneCount == 0)
        }
    }

    private func updateTarget(_ pile: SortPile, inside: Bool) {
        targeted = inside ? pile : (targeted == pile ? nil : targeted)
    }

    private func move(_ ids: [String], to role: HeadlineRole?) -> Bool {
        let known = Set(model.session.headlines.map(\.id))
        let valid = ids.compactMap(UUID.init(uuidString:)).filter { known.contains($0) }
        guard !valid.isEmpty else { return false }
        for id in valid { assign(id, to: role) }
        targeted = nil
        return true
    }

    private func assign(_ id: UUID, to role: HeadlineRole?) {
        guard let headline = model.session.headlines.first(where: { $0.id == id }), headline.role != role else {
            selected = nil
            return
        }
        withAnimation(movement) {
            lastMove = SortMove(id: id, text: headline.text, from: headline.role, to: role,
                                wasFlashcard: headline.isFlashcard, coachText: coachText,
                                coachReplies: coachReplies, askedAbout: askedAbout)
            model.setRole(role, for: id)
            selected = nil
        }
        if role == .backbone { challengeBackbone(id) }
        if role == .backbone, backboneCount > MapRules.maxLinks {
            coachText = String(localized: "That's \(backboneCount) backbone ideas. A backbone holds 2–4 — which of these could hang on another?")
            coachReplies = []
        }
    }

    /// The coach asks the student to justify their first backbone choices.
    private func challengeBackbone(_ id: UUID) {
        guard askedAbout.count < 2, !askedAbout.contains(id),
              let text = model.session.headlines.first(where: { $0.id == id })?.text else { return }
        askedAbout.insert(id)
        let lowered = text.lowercased()
        if lowered.contains("gland") || lowered.contains("pancreas") || lowered.contains("organ") {
            coachText = String(localized: "Why is “\(text)” backbone? Is the organ the important part — or what its hormones *do*?")
            coachReplies = [String(localized: "It makes the hormones"), String(localized: "What they do matters more")]
        } else {
            coachText = String(localized: "Why is “\(text)” backbone?")
            coachReplies = [String(localized: "Everything else depends on it"), String(localized: "It's the chapter title"), String(localized: "Just a hunch")]
        }
    }

    private func answer(_ reply: String) {
        let lowered = reply.lowercased()
        let text: String
        if lowered.contains("depends") || lowered.contains("do matters") {
            text = String(localized: "That's a backbone reason. Keep going.")
        } else if lowered.contains("makes the hormones") {
            text = String(localized: "That's *where* they come from. Keep it for now — we'll test it on the map.")
        } else if lowered.contains("chapter title") {
            text = String(localized: "A title names the topic — it rarely *explains* it. It may end up as your map's title instead.")
        } else {
            text = String(localized: "Fair. You'll test the hunch on the map — I'll ask again there.")
        }
        withAnimation(movement) {
            coachText = text
            coachReplies = []
        }
    }
}

private enum SortPile: Equatable {
    case unsorted
    case role(HeadlineRole)
}

private struct SortMove {
    let token = UUID()
    let id: UUID
    let text: String
    let from: HeadlineRole?
    let to: HeadlineRole?
    let wasFlashcard: Bool
    let coachText: String
    let coachReplies: [String]
    let askedAbout: Set<UUID>
}
