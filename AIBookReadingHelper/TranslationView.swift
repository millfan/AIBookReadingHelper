import SwiftUI
import Translation

/// What the translation part of the side panel is showing.
enum TranslationState: Equatable {
    case idle
    case translating
    case done(String)
    case failed(String)
}

/// The text and direction to translate. A change to either starts a new translation.
private struct TranslationRequest: Equatable {
    let text: String
    let direction: TranslationDirection
}

extension Font {
    /// The font for the selected text and its translation: twice the normal system size, so both are easy to read.
    static let readingText = Font.system(size: NSFont.systemFontSize * 2)
}

/// How long to wait after the selection stops changing before translating, so dragging doesn't send a request per word.
private let selectionSettleDelay = Duration.milliseconds(400)

/// Translates the selected text with the engine chosen in the View menu, and shows a word's dictionary definition below it.
struct TranslationView: View {
    let text: String
    let engine: TranslationEngine
    let direction: TranslationDirection
    let dictionaryWord: String?

    var body: some View {
        switch engine {
        case .google:
            GoogleTranslationView(text: text, direction: direction, dictionaryWord: dictionaryWord)
        case .apple:
            if #available(macOS 15.0, *) {
                AppleTranslationView(text: text, direction: direction, dictionaryWord: dictionaryWord)
            } else {
                TranslationResultView(state: .failed("Apple Translation needs macOS 15 or later. Choose View > Google Translation instead."),
                                      dictionaryWord: dictionaryWord)
            }
        }
    }
}

private struct GoogleTranslationView: View {
    let text: String
    let direction: TranslationDirection
    let dictionaryWord: String?
    @AppStorage(SettingsKey.googleAPIKey) private var apiKey = ""
    @State private var state = TranslationState.idle

    var body: some View {
        Group {
            if apiKey.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google Translation needs a Google Cloud API key.")
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Text("Add API Key…")
                    }
                }
            } else {
                TranslationResultView(state: state, dictionaryWord: dictionaryWord)
            }
        }
        .task(id: [text, direction.rawValue, apiKey]) {
            await translate()
        }
    }

    private func translate() async {
        guard !text.isEmpty, !apiKey.isEmpty else {
            state = .idle
            return
        }
        try? await Task.sleep(for: selectionSettleDelay)
        guard !Task.isCancelled else { return }
        state = .translating
        do {
            let translation = try await GoogleTranslator.translate(text,
                                                                  from: direction.source.googleCode,
                                                                  to: direction.target.googleCode,
                                                                  apiKey: apiKey)
            guard !Task.isCancelled else { return }
            state = .done(translation)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationView: View {
    let text: String
    let direction: TranslationDirection
    let dictionaryWord: String?
    @State private var state = TranslationState.idle
    @State private var configuration: TranslationSession.Configuration?
    @State private var pendingText = ""

    var body: some View {
        TranslationResultView(state: state, dictionaryWord: dictionaryWord)
            .translationTask(configuration) { session in
                let text = pendingText
                do {
                    let response = try await session.translate(text)
                    // Ignore a result for a selection that has since changed.
                    guard text == pendingText else { return }
                    state = .done(response.targetText)
                } catch {
                    guard text == pendingText else { return }
                    state = .failed(error.localizedDescription)
                }
            }
            .task(id: TranslationRequest(text: text, direction: direction)) {
                guard !text.isEmpty else {
                    pendingText = ""
                    state = .idle
                    return
                }
                try? await Task.sleep(for: selectionSettleDelay)
                guard !Task.isCancelled else { return }
                pendingText = text
                state = .translating
                // Both languages are named, so Apple never has to detect the source. macOS asks to download languages it doesn't have yet.
                let source = Locale.Language(identifier: direction.source.appleCode)
                let target = Locale.Language(identifier: direction.target.appleCode)
                if configuration?.source == source, configuration?.target == target {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: source, target: target)
                }
            }
    }
}

/// The translation, or how it is going, followed by the dictionary definition in one scrolling view.
private struct TranslationResultView: View {
    let state: TranslationState
    let dictionaryWord: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .idle:
                Text("The translation of the selected text appears here.")
                    .foregroundStyle(.secondary)
            case .translating:
                ProgressView("Translating…")
                    .controlSize(.small)
            case .done:
                EmptyView()
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            }
            let content = combinedText
            if content.length > 0 {
                SelectableTextView(attributedText: content)
            }
            if case .done(let translation) = state {
                Button("Copy translation", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translation, forType: .string)
                }
                .focusable(false)
            }
        }
    }

    /// The translation in the reading size, then a heading and the definition of the word, if there is one.
    private var combinedText: NSAttributedString {
        let text = NSMutableAttributedString()
        if case .done(let translation) = state {
            text.append(NSAttributedString(string: translation,
                                           attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize * 2),
                                                        .foregroundColor: NSColor.labelColor]))
        }
        guard let dictionaryWord else { return text }

        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacingBefore = text.length > 0 ? 18 : 0
        heading.paragraphSpacing = 6
        if text.length > 0 {
            text.append(NSAttributedString(string: "\n"))
        }
        text.append(NSAttributedString(string: "DICTIONARY",
                                       attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize * 0.9),
                                                    .foregroundColor: NSColor.secondaryLabelColor,
                                                    .kern: 1.0,
                                                    .paragraphStyle: heading]))
        text.append(NSAttributedString(string: "\n"))
        text.append(WordDictionary.attributedDefinition(of: dictionaryWord, fontSize: NSFont.systemFontSize * 1.4))
        return text
    }
}
