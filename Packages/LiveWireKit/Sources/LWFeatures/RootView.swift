import LWLogging
import LWModels
import SwiftUI

/// The app's only entry point. The Xcode app target does nothing but show this.
public struct RootView: View {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView()
            case .signedOut:
                SignInView(model: model)
            case .ready:
                MainTabs(model: model)
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.didBecomeActive() } }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil && model.phase == .ready },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct MainTabs: View {
    let model: AppModel

    var body: some View {
        TabView {
            NavigationStack { DashboardView(model: model) }
                .tabItem { Label("Bikes", systemImage: "bolt.batteryblock") }
            NavigationStack { RidesView(model: model) }
                .tabItem { Label("Rides", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
