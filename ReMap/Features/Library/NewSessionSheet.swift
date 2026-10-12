import SwiftUI
import UniformTypeIdentifiers

/// Pick a study source: a PDF, pasted notes, a lecture link, or the built-in example.
struct NewSessionSheet: View {
    var onCreated: (UUID) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private enum Mode { case choose, text, youtube }
    @State private var mode: Mode = .choose
    @State private var showImporter = false
    @State private var title = ""
    @State private var text = ""
    @State private var link = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .choose: chooser
                case .text: textForm
                case .youtube: youtubeForm
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.canvas)
            .navigationTitle(String(localized: "New map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close"), systemImage: "xmark") { dismiss() }
                }
                if mode != .choose {
                    ToolbarItem(placement: .navigation) {
                        Button(String(localized: "Back"), systemImage: "chevron.left") { withAnimation(Motion.snappy) { mode = .choose } }
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    do { onCreated(try app.importPDF(from: url)) } catch { self.error = error.localizedDescription }
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
            .alert(String(localized: "Couldn't import"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: { Text(error ?? "") }
        }
        .remapFormPresentation()
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What are you studying?")
                .font(TypeScale.title(28))
                .foregroundStyle(Palette.ink)
            Text("ReMap pulls the headlines out. Deciding what matters stays your job.")
                .font(TypeScale.hand(17))
                .foregroundStyle(Palette.ink2)
            Text("PDFs up to 20 MB and 30 pages are uploaded to your connected learning coach for keywords and source-grounded conversation.")
                .font(.caption).foregroundStyle(Palette.ink2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                SourceTile(symbol: "doc.richtext", title: String(localized: "PDF"), subtitle: String(localized: "Chapter, slides, article")) { showImporter = true }
                SourceTile(symbol: "text.quote", title: String(localized: "Notes or text"), subtitle: String(localized: "Paste anything")) { withAnimation(Motion.snappy) { mode = .text } }
                SourceTile(symbol: "play.rectangle", title: String(localized: "Lecture video"), subtitle: String(localized: "YouTube link + transcript")) { withAnimation(Motion.snappy) { mode = .youtube } }
                SourceTile(symbol: "sparkles", title: String(localized: "Try an example"), subtitle: TrainingLLMContent.title, highlighted: true) {
                    onCreated(app.createDemoSession())
                }
            }
        }
    }

    private var textForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(String(localized: "Title"), text: $title)
                .font(TypeScale.heading())
                .textFieldStyle(.plain)
                .padding(14)
                .paperCard(cornerRadius: 14, elevation: 0.3)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 260)
                .paperCard(cornerRadius: 14, elevation: 0.3)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste your notes, an article or a transcript…")
                            .foregroundStyle(Palette.ink3).padding(18).allowsHitTesting(false)
                    }
                }
            HStack {
                Spacer()
                PrimaryButton(title: String(localized: "Collect headlines"), systemImage: "arrow.right") {
                    let name = title.isEmpty ? String(localized: "My notes") : title
                    onCreated(app.createSession(title: name, source: SourceInfo(kind: .text, name: name, text: text)))
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var youtubeForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(String(localized: "https://youtube.com/watch?v=…"), text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .paperCard(cornerRadius: 14, elevation: 0.3)
            Text("Automatic transcripts arrive with the AI backend. For now, open the video's transcript, copy it and paste it here — or skip and add headlines yourself while you watch.")
                .font(TypeScale.hand(15))
                .foregroundStyle(Palette.ink2)
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 200)
                .paperCard(cornerRadius: 14, elevation: 0.3)
            HStack {
                Spacer()
                PrimaryButton(title: String(localized: "Continue"), systemImage: "arrow.right") {
                    let url = URL(string: link.trimmingCharacters(in: .whitespaces))
                    let name = url?.host() == nil ? String(localized: "Lecture") : String(localized: "Lecture video")
                    onCreated(app.createSession(title: name, source: SourceInfo(kind: .youtube, name: link, url: url, text: text)))
                }
                .disabled(URL(string: link)?.host() == nil)
            }
        }
    }
}

struct SourceTile: View {
    var symbol: String
    var title: String
    var subtitle: String
    var highlighted = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 52, height: 52)
                    .background(GrainBlob(color: highlighted ? Palette.butter : Palette.olive.opacity(0.45), seed: Double(title.count)))
                Text(title).font(TypeScale.heading(18)).foregroundStyle(Palette.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(18)
            .paperCard(cornerRadius: 18, elevation: 0.6)
        }
        .buttonStyle(.plain)
    }
}
