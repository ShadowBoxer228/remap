import SwiftUI

@main
struct ReMapApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Palette.oliveDeep)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.store.saveNow() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        ZStack {
            if onboardingDone {
                LibraryView()
                    .transition(.opacity)
            } else {
                OnboardingView { withAnimation(Motion.flow) { onboardingDone = true } }
                    .transition(.opacity)
            }
        }
        .background(PaperBackground())
    }
}
