import SwiftUI

@main
struct AIBookReadingHelperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            TranslationCommands()
            ZoomCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

/// Adds Zoom In, Zoom Out and Actual Size to the View menu, for the pages in the File and Internet views.
private struct ZoomCommands: Commands {
    @AppStorage(SettingsKey.pageZoom) private var zoom = PageZoom.normal

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Zoom In") {
                zoom = PageZoom.larger(than: zoom)
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(zoom >= PageZoom.range.upperBound)
            Button("Zoom Out") {
                zoom = PageZoom.smaller(than: zoom)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoom <= PageZoom.range.lowerBound)
            Button("Actual Size") {
                zoom = PageZoom.normal
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoom == PageZoom.normal)
            Divider()
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
