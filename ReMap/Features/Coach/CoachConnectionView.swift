import SwiftUI

struct CoachConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = CoachConnection.isEnabled
    @State private var endpoint = UserDefaults.standard.string(forKey: CoachConnection.endpointKey) ?? "https://remap-coach.vercel.app"
    @State private var token = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud coach · OpenAI Realtime") {
                    Text("When enabled, relevant map ideas, links, positions and recent messages are sent through your ReMap server to OpenAI. In voice mode, microphone audio streams to OpenAI until you mute or close voice. PDFs and sketches stay on this iPad. Use it only for content you are comfortable sharing.")
                    Toggle("Use cloud coach", isOn: $enabled)
                        .disabled(CoachConnection.validatedURL(endpoint) == nil || (token.isEmpty && CoachConnection.token == nil))
                    Text("Map review can use on-device or offline questions. Open conversation and continuous voice require the cloud connection. Relationship checks are prompts for reflection, not a fact-check of your source.")
                        .font(.footnote)
                }
                Section("Private test connection") {
                    TextField("ReMap server URL (https://…)", text: $endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Tester access token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Use the tester token supplied with your ReMap server. Never enter an OpenAI API key here.")
                        .font(.footnote)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Coach connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !enabled && token.isEmpty {
                            UserDefaults.standard.set(false, forKey: CoachConnection.enabledKey)
                            dismiss(); return
                        }
                        guard let url = CoachConnection.validatedURL(endpoint) else {
                            error = String(localized: "Enter an HTTPS server URL without credentials or query parameters."); return
                        }
                        let changed = url.absoluteString != UserDefaults.standard.string(forKey: CoachConnection.endpointKey)
                        guard !changed || !token.isEmpty else {
                            error = String(localized: "Enter the access token for this server."); return
                        }
                        guard token.isEmpty || CoachConnection.saveToken(token) else {
                            error = String(localized: "Could not save the token securely. Please try again."); return
                        }
                        UserDefaults.standard.set(url.absoluteString, forKey: CoachConnection.endpointKey)
                        UserDefaults.standard.set(enabled, forKey: CoachConnection.enabledKey)
                        dismiss()
                    }
                }
            }
        }
    }
}
