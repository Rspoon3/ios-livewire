import LWFeatures
import LWLogging
import LWServices
import SwiftUI

/// The app target is only a shell: everything lives in the `LiveWireKit` package.
@main
struct IOSLivewireApp: App {
    @State private var model: AppModel

    init() {
        // Start persistent logging before anything else can log.
        let configuration = LiveWireRuntime.bootstrap(process: .app)
        _model = State(initialValue: AppModel(configuration: configuration))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
