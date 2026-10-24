import SwiftUI
import Translation

/// What the translation part of the side panel is showing.
enum TranslationState: Equatable {
    case idle
    case translating
    case done(String)
    case failed(String)
}

/// The text and language to translate. A change to either starts a new translation.
private struct TranslationRequest: Equatable {
    let text: String
    let language: TargetLanguage
}

/// How long to wait after the selection stops changing before translating, so dragging doesn't send a request per word.
private let selectionSettleDelay = Duration.milliseconds(400)

/// Translates the selected text with the engine chosen in the View menu.
struct TranslationView: View {
    let text: String
    let engine: TranslationEngine
    let language: TargetLanguage

    var body: some View {
        switch engine {
        case .google:
            GoogleTranslationView(text: text, language: language)
        case .apple:
            if #available(macOS 15.0, *) {
                AppleTranslationView(text: text, language: language)
            } else {
                TranslationResultView(state: .failed("Apple Translation needs macOS 15 or later. Choose View > Google Translation instead."))
            }
        }
    }
}

private struct GoogleTranslationView: View {
    let text: String
    let language: TargetLanguage
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
                TranslationResultView(state: state)
            }
        }
        .task(id: [text, language.id, apiKey]) {
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
            let translation = try await GoogleTranslator.translate(text, to: language.googleCode, apiKey: apiKey)
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
    let language: TargetLanguage
    @State private var state = TranslationState.idle
    @State private var configuration: TranslationSession.Configuration?
    @State private var pendingText = ""

    var body: some View {
        TranslationResultView(state: state)
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
            .task(id: TranslationRequest(text: text, language: language)) {
                guard !text.isEmpty else {
                    pendingText = ""
                    state = .idle
                    return
                }
                try? await Task.sleep(for: selectionSettleDelay)
                guard !Task.isCancelled else { return }
                pendingText = text
                state = .translating
                // The source language is left to Apple to detect. macOS asks to download languages it doesn't have yet.
                let target = Locale.Language(identifier: language.appleCode)
                if configuration?.target == target {
                    configuration?.invalidate()
                } else {
                    configuration = TranslationSession.Configuration(source: nil, target: target)
                }
            }
    }
}

private struct TranslationResultView: View {
    let state: TranslationState

    var body: some View {
        switch state {
        case .idle:
            Text("The translation of the selected text appears here.")
                .foregroundStyle(.secondary)
        case .translating:
            ProgressView("Translating…")
                .controlSize(.small)
        case .done(let translation):
            ScrollView {
                Text(translation)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}
