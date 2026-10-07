import SwiftUI

@main
struct BibleReaderApp: App {
    init() { NavigationTitleStyle.apply() }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .commands { ReaderCommands() }
    }
}
