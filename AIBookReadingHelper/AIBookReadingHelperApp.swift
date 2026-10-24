import SwiftUI

@main
struct AIBookReadingHelperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TranslationCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

/// Adds the choice of translation engine to the top of the View menu. Apple Translation is the default.
private struct TranslationCommands: Commands {
    @AppStorage(SettingsKey.engine) private var engine = TranslationEngine.apple

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(TranslationEngine.allCases) { option in
                Toggle(option.menuTitle, isOn: Binding(
                    get: { engine == option },
                    set: { if $0 { engine = option } }
                ))
            }
            Divider()
        }
    }
}
