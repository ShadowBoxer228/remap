import SwiftUI

struct LocalCoachConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Connected automatically") {
                    Text("PDF and demo coaching use ReMap's cloud connection. No server address or access token is needed.")
                }
                Section("Your study material") {
                    Text("PDFs are read on this iPad. Relevant page excerpts, map pictures, keywords and messages are sent to OpenAI through ReMap. Voice sends microphone audio only while you talk.")
                    Text("Original PDFs, drawings and maps stay saved on this iPad. Turn off Cloud coach in Settings to disable cloud coaching.")
                }
            }
            .navigationTitle("Learning coach")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .remapFormPresentation()
    }
}
