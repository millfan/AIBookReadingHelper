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

/// Adds the choice of translation engine and direction to the top of the View menu.
/// The defaults are Apple Translation and ENG → CHN.
private struct TranslationCommands: Commands {
    @AppStorage(SettingsKey.engine) private var engine = TranslationEngine.apple
    @AppStorage(SettingsKey.direction) private var direction = TranslationDirection.englishToChinese

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(TranslationEngine.allCases) { option in
                Toggle(option.menuTitle, isOn: checkmark($engine, option))
            }
            Divider()
            ForEach(TranslationDirection.allCases) { option in
                Toggle(option.menuTitle, isOn: checkmark($direction, option))
            }
            Divider()
        }
    }

    /// A binding that is on when `selection` is `option`, and selects `option` when turned on.
    private func checkmark<Value: Equatable>(_ selection: Binding<Value>, _ option: Value) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue == option },
            set: { if $0 { selection.wrappedValue = option } }
        )
    }
}
