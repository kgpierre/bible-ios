import SwiftUI

@main
struct BibleReaderApp: App {
    @State private var tips = TipStore()
    init() { NavigationTitleStyle.apply() }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(tips)
        }
        .commands { ReaderCommands() }
    }
}
