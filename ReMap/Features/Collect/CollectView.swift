import SwiftUI
import PDFKit

/// Step 1 — priming: gather the source's headlines before drawing anything.
struct CollectView: View {
    @Bindable var model: SessionModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0
    @State private var newHeadline = ""
    @State private var editingID: UUID?
    @State private var editText = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 36) {
                sidebar
                    .frame(width: min(400, geo.size.width * 0.36))
                headlinesPanel
            }
            .padding(.horizontal, 36)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .task { await model.collectIfNeeded() }
        .task(id: model.session.headlines.count) { await stagger() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Gather the headlines.")
                .font(TypeScale.display(44))
                .foregroundStyle(Palette.ink)
            SourcePreview(session: model.session, url: app.sourceURL(for: model.session))
                .frame(height: 220)
            CoachNote(text: coachLine)
            Spacer(minLength: 0)
        }
    }

    private var coachLine: String {
        if model.isExtracting { return String(localized: "Skimming your source for its headlines…") }
        if let message = model.extractionMessage, model.session.headlines.isEmpty { return message }
        return String(localized: "Don't draw anything yet. Skim these headlines, fix the wording, add what's missing. This is priming — it gives new facts something to hold on to.")
    }

    private var headlinesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.session.headlines.count) headlines")
                    .font(TypeScale.heading())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(model.session.headlines.count)))
                Spacer()
                if let first = model.session.headlines.first?.page {
                    Text("from page \(first)").font(.caption).foregroundStyle(Palette.ink3)
                }
            }
            ScrollView {
                if model.isExtracting {
                    extractingPlaceholder
                } else {
                    FlowLayout(spacing: 10) {
                        ForEach(Array(model.session.headlines.enumerated()), id: \.element.id) { index, headline in
                            if index < revealed {
                                chip(for: headline)
                                    .transition(reduceMotion ? .opacity : .asymmetric(
                                        insertion: .offset(y: 12).combined(with: .scale(scale: 0.96)).combined(with: .opacity),
                                        removal: .offset(y: -6).combined(with: .opacity)))
                            }
                        }
                        addField
                    }
                    .padding(4)
                    .animation(reduceMotion ? .easeOut(duration: 0.18) : Motion.spawn, value: revealed)
                    .animation(reduceMotion ? .easeOut(duration: 0.18) : Motion.snappy, value: model.session.headlines)
                }
            }
            .scrollIndicators(.hidden)
            HStack {
                Text("Next you'll judge which of these really matter.")
                    .font(TypeScale.hand(16)).foregroundStyle(Palette.ink2)
                Spacer()
                PrimaryButton(title: String(localized: "Sort them"), systemImage: "arrow.right") {
                    model.advance(to: .sort)
                }
                .disabled(model.session.headlines.count < 3)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.surface.opacity(0.6)))
    }

    private var extractingPlaceholder: some View {
        VStack(spacing: 24) {
            Illustration(name: "collect_reading", maxHeight: 220)
            FlowLayout(spacing: 10) {
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Palette.surfaceSunken)
                        .frame(width: CGFloat([120, 90, 160, 110, 140, 80][i % 6]), height: 44)
                }
            }
            .shimmer()
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func chip(for headline: Headline) -> some View {
        if editingID == headline.id {
            TextField("", text: $editText)
                .font(TypeScale.hand(18, weight: 600))
                .padding(.horizontal, 16).frame(height: 46)
                .frame(minWidth: 140)
                .fixedSize()
                .paperCard(cornerRadius: 23, elevation: 1.4)
                .onSubmit {
                    model.renameHeadline(headline.id, to: editText)
                    editingID = nil
                }
        } else {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.snappy) {
                    editText = headline.text
                    editingID = headline.id
                }
            } label: {
                HeadlineChip(headline: headline)
            }
                .buttonStyle(HeadlinePressStyle())
                .accessibilityLabel(Text("Edit \(headline.text)"))
                .contextMenu {
                    Button(String(localized: "Edit"), systemImage: "pencil") {
                        editText = headline.text
                        editingID = headline.id
                    }
                    Button(String(localized: "Remove"), systemImage: "trash", role: .destructive) {
                        withAnimation(Motion.snappy) { model.removeHeadline(headline.id) }
                    }
                }
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").foregroundStyle(Palette.ink2)
            TextField(String(localized: "Add a headline"), text: $newHeadline)
                .font(TypeScale.hand(17))
                .focused($addFocused)
                .frame(width: 180)
                .onSubmit {
                    withAnimation(Motion.spawn) { model.addHeadline(newHeadline) }
                    newHeadline = ""
                    addFocused = true
                }
        }
        .padding(.horizontal, 16).frame(height: 46)
        .background(Capsule().strokeBorder(Palette.ink3, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }

    private func stagger() async {
        let total = model.session.headlines.count
        if revealed >= total { revealed = total; return }
        if reduceMotion { revealed = total; return }
        // Already-seen sessions show everything at once.
        if revealed == 0 && model.session.reachedPhases[.sort] != nil { revealed = total; return }
        while revealed < total {
            do { try await Task.sleep(for: Motion.stagger) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(Motion.spawn) { revealed += 1 }
        }
    }
}

struct HeadlineChip: View {
    var headline: Headline
    var lifted = false
    var maxTextWidth: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            if headline.level == 0 {
                Circle().fill(Palette.ink).frame(width: 7, height: 7)
            } else {
                Circle().strokeBorder(Palette.ink2, lineWidth: 1.2).frame(width: 7, height: 7)
            }
            Text(headline.text)
                .font(headline.level == 0 ? TypeScale.hand(18, weight: 680) : TypeScale.hand(17, weight: 480))
                .foregroundStyle(Palette.ink)
                .strikethrough(headline.isFlashcard, color: Palette.ink3)
                .opacity(headline.isFlashcard ? 0.6 : 1)
                .lineLimit(maxTextWidth == nil ? 1 : 2)
                .frame(maxWidth: maxTextWidth)
                .fixedSize(horizontal: false, vertical: true)
            if let page = headline.page {
                Text("p.\(page)").font(.caption2.monospacedDigit()).foregroundStyle(Palette.ink3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 46)
        .paperCard(cornerRadius: 23, elevation: lifted ? 1.8 : hovered ? 1.2 : 0.6)
        .overlay {
            Capsule().strokeBorder(Palette.oliveDeep.opacity(lifted ? 0.7 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .scaleEffect(reduceMotion ? 1 : lifted ? 1.035 : hovered ? 1.02 : 1)
        .rotationEffect(.degrees(lifted && !reduceMotion ? -1.5 : 0))
        .offset(y: reduceMotion ? 0 : lifted ? -3 : hovered ? -2 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.snappy, value: lifted)
        .animation(reduceMotion ? nil : Motion.snappy, value: hovered)
        .onHover { hovered = $0 }
        .contentShape(Capsule())
    }
}

/// A small, interruptible press, shared by the collection and sorting cards.
struct HeadlinePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: configuration.isPressed)
    }
}

/// The source, shown as a halftone cutout — the collage treatment applied live.
struct SourcePreview: View {
    var session: StudySession
    var url: URL?
    @State private var thumbnail: UIImage?
    @State private var reveal: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GrainBlob(color: Palette.olive.opacity(0.55), seed: 11)
                .frame(width: 230, height: 190)
                .offset(x: 120, y: -10)
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .modifier(HalftoneModifier(cell: 4, ink: Palette.ink, reveal: reveal))
                        .background(Palette.surface)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: session.source.kind.symbol).font(.largeTitle)
                        Text(session.source.text?.prefix(160) ?? Substring(session.source.name))
                            .font(.caption).lineLimit(6)
                    }
                    .foregroundStyle(Palette.ink2)
                    .padding(18)
                    .frame(width: 150, height: 200, alignment: .topLeading)
                    .background(Palette.surface)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            .rotationEffect(.degrees(-4))
            .overlay(alignment: .bottomTrailing) {
                Text(session.source.name)
                    .font(TypeScale.hand(14, weight: 600))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Palette.butter, in: Capsule())
                    .rotationEffect(.degrees(3))
                    .offset(x: 70, y: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard thumbnail == nil, let url else { return }
            thumbnail = await Task.detached(priority: .userInitiated) {
                PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 320, height: 420), for: .mediaBox)
            }.value
            withAnimation(.stopMotion(duration: 0.9, fps: 12)) { reveal = 1 }
        }
    }
}
