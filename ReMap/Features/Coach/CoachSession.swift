import SwiftUI
import Observation

/// The metacognition coach. It never draws the map for you: it points at one problem at a time,
/// asks a Socratic question, notices when you've fixed it, and only automates the tedious part
/// (re-wiring links) after *you* supply the idea.
@Observable
final class CoachSession {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var fromUser = false
    }

    enum Mode: Equatable {
        case idle
        case reviewing
        case grouping(group: UUID, hub: UUID?)
        case placing
        case finished
    }

    @ObservationIgnored weak var model: SessionModel?
    @ObservationIgnored var brain: CoachBrain

    var messages: [Message] = []
    var replies: [String] = []
    var isOpen = false
    var mode: Mode = .idle
    var isThinking = false
    private(set) var findings: [Finding] = []
    private(set) var current: Finding?
    var chosenPlacement: Placement?
    /// Nodes the student can tap to put into the group being built.
    private(set) var groupingCandidates: Set<UUID> = []
    /// Bumps whenever the coach says something new (drives text-to-speech).
    private(set) var spokenToken = 0
    private(set) var resolvedCount = 0

    @ObservationIgnored private var skipped: Set<String> = []
    @ObservationIgnored private var nextTask: Task<Void, Never>?
    @ObservationIgnored private var placementTask: Task<Void, Never>?
    @ObservationIgnored private var titleCandidate: UUID?
    @ObservationIgnored private var groupsMade: [String] = []

    init(model: SessionModel, brain: CoachBrain = CoachBrainFactory.make()) {
        self.model = model
        self.brain = brain
        self.findings = MapRules.findings(for: model.map)
    }

    var latestCoachMessage: Message? { messages.last { !$0.fromUser } }
    var issueCount: Int { findings.count }
    private var map: MindMap { model?.map ?? MindMap(title: "") }
    private var isDemo: Bool { model?.session.isDemo ?? false }

    // MARK: - Talking

    func say(_ text: String, replies: [String] = []) {
        withAnimation(Motion.snappy) {
            messages.append(Message(text: text))
            self.replies = replies
        }
        spokenToken += 1
        model?.conversation.didReceiveCoachMessage(text)
    }

    func open() {
        withAnimation(Motion.flow) { isOpen = true }
        if model?.conversation.presentation == .collapsed { model?.conversation.presentation = .chat }
        if messages.isEmpty { greet() }
    }

    func close() {
        withAnimation(Motion.flow) { isOpen = false }
        if model?.conversation.presentation == .chat { model?.conversation.presentation = .collapsed }
    }

    func greet() {
        guard let model else { return }
        if model.session.phase == .details {
            say(String(localized: "Welcome back. Hang the details on your backbone — I'll keep an eye on the structure."),
                replies: [String(localized: "Check my map")])
        } else if model.map.nodes.isEmpty {
            say(String(localized: "Start with the backbone: drag your backbone ideas from the tray onto the paper and link them. Arrows should say who acts on whom."))
        } else {
            say(String(localized: "Ready when you are. I'll question your map — one thing at a time."),
                replies: [String(localized: "Check my map")])
        }
    }

    func reset(preservingConversation: Bool = false) {
        nextTask?.cancel()
        placementTask?.cancel()
        isThinking = false
        hasCelebrated = false
        if !preservingConversation { messages = [] }
        replies = []
        mode = .idle
        current = nil
        chosenPlacement = nil
        groupingCandidates = []
        skipped = []
        groupsMade = []
        titleCandidate = nil
        resolvedCount = 0
        findings = MapRules.findings(for: map)
    }

    // MARK: - Review

    /// Stop review work while retaining the student's conversation and progress.
    func pauseReview() {
        nextTask?.cancel(); placementTask?.cancel()
        isThinking = false; current = nil; chosenPlacement = nil
        groupingCandidates = []; titleCandidate = nil; skipped = []; extraCandidates = []
        mode = .idle
        model?.cancelPlacement(); model?.clearFocus()
        findings = MapRules.findings(for: map)
    }

    func startReview() {
        guard let model else { return }
        model.conversation.prepareForPhaseChange()
        reset(preservingConversation: true)
        model.cancelPlacement()
        if model.session.phase < .check { model.advance(to: .check) }
        skipped = []
        hasCelebrated = false
        mode = .reviewing
        open()
        say(String(localized: "Let's question your map. I'll point at one thing at a time — you decide what to change."))
        scheduleNext(after: .milliseconds(1400))
    }

    private func scheduleNext(after delay: Duration) {
        nextTask?.cancel()
        nextTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.next()
        }
    }

    private func next() async {
        guard mode == .reviewing, let model else { return }
        findings = MapRules.findings(for: model.map)
        guard let finding = findings.first(where: { !skipped.contains($0.id) }) else {
            finish()
            return
        }
        current = finding
        model.point(at: finding.nodeIDs + finding.edgeIDs)
        isThinking = true
        let text = await brain.question(for: finding, in: model.map, isDemo: isDemo)
        isThinking = false
        guard !Task.isCancelled, mode == .reviewing, current == finding else { return }
        say(text, replies: replies(for: finding))
    }

    private func replies(for finding: Finding) -> [String] {
        let skip = String(localized: "Skip")
        switch finding.kind {
        case .hubIsTitle:
            return isDemo && groupsMade.isEmpty ? DemoContent.hubSuggestedAnswers
                : [String(localized: "I'm not sure"), skip]
        case .missingDirection:
            guard let a = map.node(finding.nodeIDs[0])?.label, let b = map.node(finding.nodeIDs[1])?.label else { return [skip] }
            return ["\(a) → \(b)", "\(b) → \(a)", String(localized: "They affect each other")]
        case .tooWordy:
            return [String(localized: "It's a detail — make it a flashcard"), skip]
        case .tooFewLinks:
            return [String(localized: "Unmark backbone"), skip]
        case .island, .noBackbone:
            return [skip]
        case .singleChain:
            return [String(localized: "I'm not sure"), skip]
        case .unexplainedLink:
            return [skip]
        }
    }

    /// Re-checks the map after every edit; celebrates fixes and moves on.
    func mapDidChange() {
        guard let model else { return }
        findings = MapRules.findings(for: model.map)
        refreshGroupingCandidates()
        if case .grouping = mode { return }
        guard mode == .reviewing, let finding = current else { return }
        if !findings.contains(where: { $0.id == finding.id }) {
            current = nil
            resolvedCount += 1
            model.clearFocus()
            say(praise(for: finding.kind))
            scheduleNext(after: .milliseconds(1600))
        }
    }

    private func praise(for kind: FindingKind) -> String {
        switch kind {
        case .hubIsTitle: String(localized: "Hub gone. Each group now carries its own meaning.")
        case .island: String(localized: "Connected. That bridge is where understanding lives.")
        case .missingDirection: String(localized: "Good — that arrow tells a story now.")
        case .tooWordy: String(localized: "Sharper. Fewer words, more thinking.")
        case .tooFewLinks: String(localized: "Better — a backbone idea should branch.")
        case .singleChain: String(localized: "That's a structure now, not a list.")
        case .noBackbone: String(localized: "Now the map has a spine.")
        case .unexplainedLink: String(localized: "If you can say it in one sentence, you understand it.")
        }
    }

    private func finish() {
        guard let model else { return }
        mode = .finished
        current = nil
        model.clearFocus()
        guard !model.map.nodes.isEmpty else {
            say(String(localized: "Nothing to check yet — put a few ideas on the paper first."))
            return
        }
        var next = [String(localized: "Open mind map")]
        if let headline = model.session.unplacedHeadlines.first {
            next.insert(Self.placementPrompt(for: headline.text), at: 0)
        }
        guard findings.isEmpty else {
            say(String(localized: "Review paused with \(findings.count) questions still open. Skipping keeps them for next time."),
                replies: [String(localized: "Check my map")] + next)
            return
        }
        if !hasCelebrated {
            hasCelebrated = true
            say(String(localized: "Your map holds up. Every node earns its place and every arrow says something."), replies: next)
            model.celebrate += 1
        } else {
            say(String(localized: "Still solid."), replies: next)
        }
    }

    @ObservationIgnored private var hasCelebrated = false

    static func placementPrompt(for label: String) -> String {
        String(localized: "Where does “\(label)” go?")
    }

    // MARK: - Replies

    func reply(_ text: String) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, let model else { return }
        withAnimation(Motion.snappy) {
            messages.append(Message(text: answer, fromUser: true))
            replies = []
        }
        let lowered = answer.lowercased()

        if lowered == String(localized: "Check my map").lowercased() { startReview(); return }
        if let headline = model.session.unplacedHeadlines.first(where: { Self.placementPrompt(for: $0.text).lowercased() == lowered }) {
            withAnimation(Motion.flow) { model.startPlacement(label: headline.text, headlineID: headline.id) }
            return
        }
        if lowered == String(localized: "Open mind map").lowercased() || lowered == String(localized: "Continue in a later session").lowercased() {
            model.openMindMap()
            return
        }
        if let hub = titleCandidate { handleTitleDecision(lowered, hub: hub); return }

        switch mode {
        case .placing: handlePlacementReply(answer)
        case .grouping(let group, let hub): handleGroupingReply(lowered, group: group, hub: hub)
        default:
            if let finding = current { handle(answer, lowered: lowered, for: finding) }
            else { say(String(localized: "Noted. Tap Check whenever you want me to look again."), replies: [String(localized: "Check my map")]) }
        }
    }

    private func handle(_ answer: String, lowered: String, for finding: Finding) {
        guard let model else { return }
        if lowered == String(localized: "Skip").lowercased() {
            placementTask?.cancel()
            isThinking = false
            skipped.insert(finding.id)
            current = nil
            model.clearFocus()
            scheduleNext(after: .milliseconds(300))
            return
        }
        switch finding.kind {
        case .hubIsTitle, .singleChain:
            let organWords = ["pancreas", "gland", "organ", "come from", "made", "produced", "secrete"]
            if isDemo && organWords.contains(where: lowered.contains) {
                say(isDemo ? DemoContent.organAnswerReply
                    : String(localized: "That's *where* they come from — an address, not a meaning. What do they *do* in common?"),
                    replies: isDemo ? [String(localized: "Blood sugar")] : [String(localized: "I'm not sure")])
            } else if lowered.contains("not sure") {
                say(isDemo ? String(localized: "Hint: one of them lowers blood sugar, the other raises it.")
                    : String(localized: "Pick any two of them and ask: what changes when they act?"),
                    replies: isDemo ? [String(localized: "Blood sugar")] : [])
            } else {
                startGroup(named: answer, hub: finding.kind == .hubIsTitle ? finding.nodeIDs.first : nil,
                           members: finding.kind == .singleChain ? finding.nodeIDs : nil)
            }
        case .missingDirection:
            guard let edgeID = finding.edgeIDs.first, let edge = map.edges.first(where: { $0.id == edgeID }),
                  let a = map.node(edge.from)?.label else { return }
            if lowered.contains("each other") {
                say(String(localized: "Then which effect matters more for this topic? Pick the stronger one — that's the judgment."),
                    replies: replies(for: finding).dropLast().map { $0 })
            } else {
                let b = map.node(edge.to)?.label ?? ""
                guard answer == "\(a) → \(b)" || answer == "\(b) → \(a)" else {
                    say(String(localized: "Choose the arrow direction below, or change it on the map."), replies: replies(for: finding))
                    return
                }
                let forward = answer == "\(a) → \(b)"
                withAnimation(Motion.snappy) { model.setDirection(forward ? .forward : .backward, for: edgeID) }
            }
        case .tooWordy:
            guard let nodeID = finding.nodeIDs.first, let node = map.node(nodeID) else { return }
            if lowered.contains("flashcard") {
                withAnimation(Motion.snappy) {
                    model.update { $0.headlines.append(Headline(text: node.label, role: .detail, isFlashcard: true)) }
                    model.deleteNode(nodeID)
                }
            } else {
                let words = answer.split(separator: " ").count
                if words <= MapRules.maxWords {
                    withAnimation(Motion.snappy) { model.renameNode(nodeID, to: answer) }
                } else {
                    say(String(localized: "Still \(words) words. Shorter — what's the one idea?"), replies: replies(for: finding))
                }
            }
        case .tooFewLinks:
            if lowered.contains("unmark"), let id = finding.nodeIDs.first {
                withAnimation(Motion.snappy) { model.toggleBackbone(id) }
            } else {
                say(String(localized: "Draw that link on the paper — drag from the node's arrow handle."))
            }
        case .unexplainedLink:
            guard !isThinking, let edgeID = finding.edgeIDs.first,
                  let edge = map.edges.first(where: { $0.id == edgeID }),
                  let first = map.node(edge.from), let second = map.node(edge.to) else { return }
            isThinking = true
            placementTask = Task { [weak self] in
                guard let self else { return }
                let grounded = await brain.judge(reason: answer, label: first.label, parent: second.label)
                guard !Task.isCancelled, mode == .reviewing, current == finding else { return }
                isThinking = false
                guard model.map.edges.contains(edge), model.map.node(first.id)?.label == first.label,
                      model.map.node(second.id)?.label == second.label else { return }
                if grounded { model.setReason(answer, for: edgeID) }
                else {
                    say(String(localized: "Explain how these two ideas are related. A reason about their position is not enough."),
                        replies: [String(localized: "Skip")])
                }
            }
        case .island, .noBackbone:
            say(String(localized: "Do it on the paper — I'll notice."))
        }
    }

    // MARK: - Grouping (the hub split)

    /// The student named what some ideas share; make it a group node and let them pick its members.
    private func startGroup(named raw: String, hub: UUID?, members: [UUID]?) {
        guard let model else { return }
        guard raw.split(whereSeparator: \.isWhitespace).count <= MapRules.maxWords else {
            say(String(localized: "Name the shared idea in 1–3 words. What would you write on that group?"))
            return
        }
        nextTask?.cancel()
        current = nil
        let name = Self.cleanGroupName(raw)
        let anchor = hub.flatMap { map.node($0)?.position } ?? members.flatMap { $0.first }.flatMap { map.node($0)?.position } ?? DemoContent.center
        let usedGroups = Set(map.nodes.compactMap(\.group))
        let groupIndex = (0..<Palette.branches.count).first { !usedGroups.contains($0) } ?? groupsMade.count
        let spot = PlacementSuggester.suggest(for: name, in: map, count: 6)
            .min { $0.position.distance(to: anchor) < $1.position.distance(to: anchor) }?.position
            ?? CGPoint(x: anchor.x, y: anchor.y + 220)
        var groupID = UUID()
        withAnimation(Motion.spawn) {
            groupID = model.addNode(name, at: spot, backbone: true, from: anchor)
            model.setGroup(groupIndex, for: groupID)
            if let hub { model.connect(hub, groupID) }
        }
        groupsMade.append(name)
        mode = .grouping(group: groupID, hub: hub)
        refreshGroupingCandidates(extra: members)
        model.point(at: Array(groupingCandidates))
        say(String(localized: "Nice — “\(name)” is a group now. Tap the ideas that belong to it."),
            replies: [String(localized: "Done")])
    }

    static func cleanGroupName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let words = trimmed.split(separator: " ").prefix(MapRules.maxWords)
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    @ObservationIgnored private var extraCandidates: Set<UUID> = []

    private func refreshGroupingCandidates(extra: [UUID]? = nil) {
        if let extra { extraCandidates = Set(extra) }
        guard case .grouping(let group, let hub) = mode else {
            groupingCandidates = []
            return
        }
        var candidates = extraCandidates
        if let hub {
            candidates.formUnion(map.neighbors(of: hub).filter { id in
                id != group && map.node(id)?.isBackbone == false
            })
        }
        candidates.remove(group)
        candidates.subtract(map.neighbors(of: group))
        groupingCandidates = candidates
    }

    /// Moves a tapped idea into the current group: re-wires its link and slides it next to the group.
    func assignToGroup(_ nodeID: UUID) {
        guard let model, case .grouping(let group, let hub) = mode, let groupNode = map.node(group) else { return }
        if let hub, map.edge(between: nodeID, and: hub) != nil {
            model.rewire(nodeID, from: hub, to: group)
        } else {
            model.connect(nodeID, group)
        }
        model.setGroup(groupNode.group, for: nodeID)
        let children = map.neighbors(of: group).filter { $0 != hub }
        let fan = LayoutEngine.fan(children: children, around: groupNode.position,
                                   awayFrom: hub.flatMap { map.node($0)?.position } ?? map.bounds.center)
        model.setPositions(fan, undoable: false)
        refreshGroupingCandidates()
        model.point(at: Array(groupingCandidates))
    }

    private func handleGroupingReply(_ lowered: String, group: UUID, hub: UUID?) {
        guard let model else { return }
        guard lowered == String(localized: "Done").lowercased() else {
            say(String(localized: "Tap the ideas that belong to the group, then say Done."), replies: [String(localized: "Done")])
            return
        }
        guard map.neighbors(of: group).contains(where: { $0 != hub }) else {
            say(String(localized: "Pick at least one idea for this group before moving on."), replies: [String(localized: "Done")])
            return
        }
        let groupName = map.node(group)?.label.lowercased() ?? ""
        mode = .reviewing
        groupingCandidates = []
        extraCandidates = []
        model.clearFocus()
        let leftovers = hub.map { h in map.neighbors(of: h).filter { map.node($0)?.isBackbone == false } } ?? []
        if let hub, !leftovers.isEmpty {
            current = Finding(kind: .hubIsTitle, nodeIDs: [hub])
            model.point(at: leftovers)
            let followUp = DemoContent.groupFollowUps.first { groupName.contains($0.key) }?.value
            say(isDemo ? (followUp ?? String(localized: "And the rest? What do some of them share?"))
                : String(localized: "And the rest? What do some of them share?"),
                replies: isDemo ? demoReplies(after: groupName) : [String(localized: "I'm not sure"), String(localized: "Skip")])
        } else if let hub, let hubNode = map.node(hub) {
            if let followUp = DemoContent.groupFollowUps.first(where: { groupName.contains($0.key) })?.value, isDemo {
                say(followUp)
            }
            titleCandidate = hub
            current = nil
            say(String(localized: "Now “\(hubNode.label)” only connects groups — it has become a title. Make it the map's title?"),
                replies: [String(localized: "Make it the title"), String(localized: "Keep it as a node")])
        } else {
            current = nil
            scheduleNext(after: .milliseconds(1200))
        }
    }

    private func demoReplies(after groupName: String) -> [String] {
        if groupName.contains("sugar") { return [String(localized: "Stress"), String(localized: "They come from the adrenal glands")] }
        if groupName.contains("stress") { return [String(localized: "Blood calcium")] }
        return [String(localized: "I'm not sure")]
    }

    private func handleTitleDecision(_ lowered: String, hub: UUID) {
        guard let model else { return }
        titleCandidate = nil
        if lowered.contains("title") {
            withAnimation(Motion.flow) { model.promoteToTitle(hub) }
            say(String(localized: "Done — it's the title now. Notice anything? Your groups just became islands. That's the next lesson: connect them."))
        } else {
            say(String(localized: "Fine — keep it if it carries meaning beyond a title."))
        }
        mode = .reviewing
        scheduleNext(after: .milliseconds(2400))
    }

    // MARK: - Placement

    func beginPlacement(label: String) {
        nextTask?.cancel()
        placementTask?.cancel()
        isThinking = false
        current = nil
        mode = .placing
        chosenPlacement = nil
        open()
        say(String(localized: "Where does “\(label)” belong? Three spots, three different stories — pick one."),
            replies: [String(localized: "Cancel")])
    }

    func choose(_ placement: Placement) {
        guard let model else { return }
        placementTask?.cancel()
        isThinking = false
        chosenPlacement = placement
        let parent = map.node(placement.parentID)?.label ?? ""
        let label = model.placingLabel ?? ""
        let suggestions = isDemo ? (DemoContent.placementReasonSuggestions[label] ?? []) : []
        say(String(localized: "Why next to “\(parent)”?"),
            replies: suggestions.isEmpty ? [String(localized: "It just fit there"), String(localized: "Cancel")] : suggestions)
    }

    private func handlePlacementReply(_ answer: String) {
        guard let model else { return }
        if answer.lowercased() == String(localized: "Cancel").lowercased() {
            placementTask?.cancel()
            isThinking = false
            withAnimation(Motion.flow) { model.cancelPlacement() }
            mode = .reviewing
            say(String(localized: "No problem. Place it whenever you're ready."))
            return
        }
        guard let placement = chosenPlacement else {
            say(String(localized: "Pick one of the three spots first."), replies: [String(localized: "Cancel")])
            return
        }
        let label = model.placingLabel ?? ""
        let parent = map.node(placement.parentID)?.label ?? ""
        guard !isThinking else { return }
        isThinking = true
        placementTask = Task { [weak self] in
            guard let self else { return }
            let grounded = await brain.judge(reason: answer, label: label, parent: parent)
            guard !Task.isCancelled, mode == .placing,
                  chosenPlacement?.id == placement.id, model.placingLabel == label else { return }
            isThinking = false
            if grounded {
                say(String(localized: "Grounded in a relationship. I saved your reason on the arrow — check it against your source."))
                withAnimation(Motion.spawn) { model.commitPlacement(placement, reason: answer) }
                mode = .reviewing
                scheduleNext(after: .milliseconds(1800))
            } else {
                say(String(localized: "Explain the relationship more clearly: what does “\(label)” *do* to “\(parent)”?"),
                    replies: isDemo ? (DemoContent.placementReasonSuggestions[label] ?? []) : [String(localized: "Cancel")])
            }
        }
    }
}
