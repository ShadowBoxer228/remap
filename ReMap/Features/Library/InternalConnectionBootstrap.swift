import Foundation

enum InternalConnectionBootstrap {
    private static let completedKey = "internalConnectionProvisioned.v1"

    /// First-launch TestFlight access finishes before cover scheduling; opt-out wins.
    static func prepareCloudAccess() async {
        configureIfAvailable()
        await CoachEnrollment.shared.warmUp()
    }

    /// Internal install tooling places this file in app data, never in source or a public binary.
    static func configureIfAvailable() {
        #if DEBUG
        // Defaults are ready-to-use; an explicit later opt-out always wins.
        UserDefaults.standard.register(defaults: [
            CoachConnection.enabledKey: true,
            CoachConnection.endpointKey: "https://remap-coach.vercel.app",
            CoverStore.enabledKey: true
        ])
        let file = URL.applicationSupportDirectory.appending(path: "ReMap/InternalConnection.plist")
        guard let data = try? Data(contentsOf: file),
              let config = try? PropertyListDecoder().decode(Configuration.self, from: data),
              let url = CoachConnection.validatedURL(config.endpoint),
              config.token.count >= 32,
              CoachConnection.saveToken(config.token) else { return }
        let defaults = UserDefaults.standard
        defaults.set(url.absoluteString, forKey: CoachConnection.endpointKey)
        if !defaults.bool(forKey: completedKey) {
            defaults.set(true, forKey: CoachConnection.enabledKey)
            if defaults.object(forKey: CoverStore.enabledKey) == nil {
                defaults.set(true, forKey: CoverStore.enabledKey)
            }
            defaults.set(true, forKey: completedKey)
        }
        // Subsequent provisioning may rotate a token but must respect the user's switches.
        try? FileManager.default.removeItem(at: file)
        #endif
    }

    private struct Configuration: Decodable {
        let endpoint: String
        let token: String
    }
}
