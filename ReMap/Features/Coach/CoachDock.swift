import SwiftUI

/// A stable session-backed entry point for the canvas and the earlier study phases.
/// Moving this view between docks never starts or stops the audio session.
struct CoachDock: View {
    @Bindable var model: SessionModel
    var width: CGFloat = 340
    var maxHeight: CGFloat = 480
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var conversation: CoachConversation = model.conversation
        VStack(spacing: 8) {
            if model.session.usesLocalCoach && !conversation.sourceReferences.isEmpty {
                HStack {
                    ForEach(conversation.sourceReferences) { reference in
                        Button("Page \(reference.page)") { conversation.openSource(page: reference.page) }
                            .remapButtonStyle()
                            .accessibilityHint(reference.reason)
                    }
                }
            }
            switch conversation.presentation {
            case .collapsed:
                EmptyView()
            case .chat:
                CoachPanel(model: model, coach: model.coach, draft: $conversation.draft,
                           width: width, maxHeight: maxHeight)
            case .voice:
                VoiceOverlay(model: model, width: width, maxHeight: maxHeight)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: conversation.presentation)
        .sheet(isPresented: $conversation.showingSource) {
            TrainingSourceSheet(session: model.session, page: conversation.selectedSourcePage, passages: conversation.sourcePassages)
        }
    }
}

extension CoachCharacterState {
    init(_ activity: CoachActivity) {
        switch activity {
        case .idle: self = .idle
        case .connecting: self = .connecting
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .speaking: self = .speaking
        case .muted: self = .muted
        case .unavailable: self = .unavailable
        }
    }
}

/// The header's only coach entry point. No separate microphone or status pill.
struct CoachLauncher: View {
    var state: CoachCharacterState = .idle
    var isExpanded = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CoachCharacter(size: 52, state: state)
                .contentShape(Rectangle())
        }
        .buttonStyle(CoachLauncherStyle())
        .accessibilityLabel(String(localized: "Coach"))
        .accessibilityValue(isExpanded ? String(localized: "Open") : String(localized: "Minimized"))
        .accessibilityHint(String(localized: "Open your conversation with the coach"))
        .accessibilityIdentifier("coach.launcher")
        .help(String(localized: "Talk or write to your coach"))
    }
}

private struct CoachLauncherStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Rendering-only chat; the draft and history are owned by the study session.
struct CoachChatCard: View {
    var messages: [CoachSession.Message]
    var replies: [String]
    @Binding var draft: String
    var status: String
    var thinking: Bool
    var width: CGFloat = 340
    var maxHeight: CGFloat = 480
    var actionSummary: String?
    var canUndoAction = false
    var send: (String) -> Void
    var startVoice: () -> Void
    var close: () -> Void
    var review: (() -> Void)?
    var undo: () -> Void = {}
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool { maxHeight < 280 }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach").font(TypeScale.heading(19)).foregroundStyle(Palette.ink)
                    if !compact {
                        Text(status).font(.caption).foregroundStyle(Palette.ink2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if compact {
                    if !replies.isEmpty || review != nil || canUndoAction {
                        Menu {
                            ForEach(replies, id: \.self) { reply in
                                Button(reply) { send(reply) }.disabled(thinking)
                            }
                            if let review {
                                Button(String(localized: "Check my map"), systemImage: "square.and.pencil", action: review)
                                    .disabled(thinking)
                            }
                            if canUndoAction {
                                Button(String(localized: "Undo coach change"), systemImage: "arrow.uturn.backward", action: undo)
                            }
                        } label: {
                            Image(systemName: "ellipsis.bubble")
                        }
                        .buttonStyle(CoachControlStyle(tone: .quiet))
                        .accessibilityLabel(String(localized: "Coach suggestions and actions"))
                        .accessibilityIdentifier("coach.actions")
                    }
                    CoachIconButton(label: String(localized: "Talk to the coach"), symbol: "mic", tone: .quiet) {
                        typing = false
                        startVoice()
                    }
                    .accessibilityIdentifier("coach.startVoice")
                } else {
                    Button {
                        typing = false
                        startVoice()
                    } label: {
                        Label(String(localized: "Talk"), systemImage: "mic")
                            .fixedSize()
                    }
                    .buttonStyle(CoachControlStyle(tone: .paper))
                    .accessibilityLabel(String(localized: "Talk to the coach"))
                    .accessibilityIdentifier("coach.startVoice")
                }
                CoachIconButton(label: String(localized: "Minimize coach"), symbol: "chevron.down", tone: .quiet) {
                    typing = false
                    close()
                }
                .accessibilityIdentifier("coach.minimize")
            }

            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            HStack(alignment: .bottom, spacing: 6) {
                TextField(String(localized: "Ask, explain, or change your map…"), text: $draft, axis: .vertical)
                    .font(TypeScale.hand(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...(compact ? 1 : 3))
                    .focused($typing)
                    .submitLabel(.send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Palette.surfaceSunken.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(String(localized: "Message to coach"))
                    .accessibilityIdentifier("coach.input")
                    .onSubmit(submit)
                CoachIconButton(label: String(localized: "Send message"), symbol: "arrow.up", tone: .primary, action: submit)
                    .disabled(!hasDraft || thinking)
                    .accessibilityIdentifier("coach.send")
            }
        }
        .padding(compact ? 10 : 16)
        .frame(width: width, height: maxHeight)
        .modifier(CoachPaperSurface())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: thinking)
        .accessibilityIdentifier("coach.chat")
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                    ForEach(messages) { message in
                        messageView(message).id(message.id)
                    }
                    if thinking {
                        HStack(spacing: 8) {
                            CoachCharacter(size: 24, state: .thinking)
                            Text("Thinking…").font(.caption).foregroundStyle(Palette.ink2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if !compact, let actionSummary {
                        CoachActionReceipt(summary: actionSummary, canUndo: canUndoAction, undo: undo)
                    }
                    if !compact && !replies.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(replies, id: \.self) { reply in
                                Button(reply) { send(reply) }
                                    .buttonStyle(CoachControlStyle())
                                    .disabled(thinking)
                            }
                        }
                    }
                    if !compact, let review {
                        Button(action: review) {
                            Label(String(localized: "Check my map"), systemImage: "square.and.pencil")
                        }
                        .buttonStyle(CoachControlStyle(tone: .quiet))
                        .disabled(thinking)
                    }
                    Color.clear.frame(height: 1).id("coach-bottom")
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .remapChatAlignment { proxy.scrollTo("coach-bottom", anchor: .bottom) }
            .onChange(of: messages.last?.text) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("coach-bottom", anchor: .bottom)
                }
            }
            .onChange(of: thinking) { _, _ in
                proxy.scrollTo("coach-bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: CoachSession.Message) -> some View {
        if message.fromUser {
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.butter.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(String(localized: "You: \(message.text)"))
        } else {
            Text((try? AttributedString(markdown: message.text)) ?? AttributedString(message.text))
                .font(TypeScale.coach(compact ? 16 : 18))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(String(localized: "Coach: \(message.text)"))
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        draft = ""
        send(text)
    }
}

/// A talking figure on the paper itself, with no card or full-screen surface.
struct CoachVoiceCompanion: View {
    var state: CoachCharacterState
    var level: Double
    var caption: String
    var status: String
    var provider: String
    var muted: Bool
    var error: String?
    var width: CGFloat = 220
    var maxHeight: CGFloat = 300
    var actionSummary: String?
    var canUndoAction = false
    var toggleMicrophone: () -> Void
    var openChat: () -> Void
    var end: () -> Void
    var retry: () -> Void
    var undo: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool { width < 200 || maxHeight < 250 }
    private var figureSize: CGFloat { min(compact ? 112 : 160, max(64, maxHeight - 144)) }
    private var captionText: String { error ?? (caption.isEmpty ? captionPlaceholder : caption) }

    private var orbState: VoiceSession.State {
        switch state {
        case .listening: .listening
        case .speaking: .speaking
        case .connecting, .thinking: .thinking
        case .unavailable: .unavailable(error ?? "")
        default: .idle
        }
    }

    private var captionPlaceholder: String {
        switch state {
        case .idle: String(localized: "Ready when you are")
        case .connecting: String(localized: "Connecting your voice…")
        case .listening: String(localized: "I'm listening")
        case .thinking: String(localized: "Thinking about your question…")
        case .speaking: String(localized: "Live captions will appear here")
        case .muted: String(localized: "Your microphone is off")
        case .unavailable: String(localized: "We can keep talking in chat")
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            VoiceOrb(state: orbState, level: level, muted: muted)
                .frame(width: figureSize, height: figureSize)
                .padding(.vertical, 14)

            Text(captionText)
                .font(error == nil ? TypeScale.coach(compact ? 16 : 18) : .caption)
                .foregroundStyle(error != nil ? Palette.accent : caption.isEmpty ? Palette.ink2 : Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(maxHeight < 220 ? 1 : 3)
                .truncationMode(.head)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: captionText)
                .accessibilityLabel(captionText)
                .accessibilityIdentifier("coach.captions")

            HStack(spacing: compact ? 0 : 4) {
                if error != nil {
                    CoachIconButton(label: String(localized: "Try again"), symbol: "arrow.clockwise", tone: .quiet, action: retry)
                        .accessibilityIdentifier("coach.retry")
                } else {
                    CoachIconButton(label: muted ? String(localized: "Turn microphone on") : String(localized: "Mute microphone"),
                                    symbol: muted ? "mic.slash" : "mic.fill", tone: .quiet,
                                    action: toggleMicrophone)
                        .disabled(state == .connecting)
                        .accessibilityIdentifier("coach.microphone")
                }
                CoachIconButton(label: String(localized: "Return to chat"), symbol: "text.bubble", tone: .quiet, action: openChat)
                    .accessibilityIdentifier("coach.returnToChat")
                if canUndoAction {
                    CoachIconButton(label: String(localized: "Undo coach change"), symbol: "arrow.uturn.backward", tone: .quiet, action: undo)
                        .accessibilityHint(actionSummary ?? "")
                }
                CoachIconButton(label: String(localized: "End conversation"), symbol: "xmark", tone: .quiet, action: end)
                    .accessibilityIdentifier("coach.endVoice")
            }
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight, alignment: .top)
        // A soft wash of paper keeps captions legible over busy content without a card.
        .background {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(Palette.canvas.opacity(0.9))
                .padding(-14)
                .blur(radius: 16)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Voice coach"))
        .accessibilityValue(status)
        .accessibilityHint(provider)
        .accessibilityIdentifier("coach.voice")
    }
}
