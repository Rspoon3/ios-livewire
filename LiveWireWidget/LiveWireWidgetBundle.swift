import LWLogging
import LWServices
import LWWidgets
import SwiftUI
import WidgetKit

/// The extension target is only a shell: the widget lives in the `LiveWireKit` package.
@main
struct LiveWireWidgetBundle: WidgetBundle {
    init() {
        LiveWireRuntime.bootstrap(process: .widget)
    }

    var body: some Widget {
        BatteryWidget()
    }
}
