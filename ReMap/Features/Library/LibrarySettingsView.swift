import SwiftUI

struct LibrarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloudCoachEnabled") private var coachEnabled = true
    @AppStorage("automaticTopicCovers") private var coversEnabled = true
    @State private var connecting = false
    @State private var showLearningCoach = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud features") {
                    Toggle("Cloud coach", isOn: $coachEnabled)
                    Toggle("Automatic topic covers", isOn: $coversEnabled)
                }
                Section {
                    Text("The coach sends relevant map labels and your messages to OpenAI through ReMap. Voice uses the microphone only when you start a voice conversation.")
                    Text("Topic covers send the topic title and up to six headlines to fal.ai. Your PDFs, full notes and sketches stay on this iPad.")
                    Text("Saved covers and maps remain available offline. When cloud coaching is unavailable, ReMap uses its on-device coach or offline questions.")
                } header: { Text("Your study material") }
                Section {
                    Button("Learning coach", systemImage: "network") { showLearningCoach = true }
                        .accessibilityIdentifier("settings.learningCoach")
                    Text("PDF and demo coaching connect automatically through ReMap. Relevant PDF excerpts, keywords, messages and pictures of your map are sent to OpenAI. Original PDF files remain on this iPad.")
                } header: { Text("Learning coach") }
                if CoachConnection.token == nil {
                    Section {
                        Text("ReMap connects automatically in this internal build. If the connection is unavailable, you can keep working on your maps and retry later.")
                        Button(connecting ? "Connecting…" : "Retry connection") {
                            connecting = true
                            Task {
                                await CoachEnrollment.shared.warmUp()
                                connecting = false
                            }
                        }
                        .disabled(connecting || !coachEnabled)
                    }
                }
            }
            .tint(Palette.oliveDeep)
            .sheet(isPresented: $showLearningCoach) { LocalCoachConnectionView() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .remapFormPresentation()
    }
}
