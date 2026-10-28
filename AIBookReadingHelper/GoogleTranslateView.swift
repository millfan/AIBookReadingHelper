import SwiftUI
import WebKit

/// Google Translate's web page in the side panel, in place of the selected text and translation. Text selected on the
/// page is put into its input box, translated the way the View menu's direction says.
struct GoogleTranslateView: View {
    let selectedText: String
    /// Whether the view is showing. The selection is only put into the input box while it is.
    let isShowing: Bool
    /// Whether the reader is typing in the page, where Space and Esc must type rather than act as shortcuts.
    @Binding var isTyping: Bool
    @AppStorage(SettingsKey.direction) private var direction = TranslationDirection.englishToChinese
    /// The selection to translate, once it has stopped changing.
    @State private var textToTranslate = ""
    @State private var reloadCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Google Translate")
                    .font(.headline)
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") {
                    reloadCount += 1
                }
                .labelStyle(.iconOnly)
                .help("Translate the selected text again")
                .focusable(false)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            GoogleTranslateWebView(address: address, reloadCount: reloadCount, isTyping: $isTyping)
        }
        // Waits for the selection to settle, so dragging across the page doesn't reload the page per word.
        .task(id: [selectedText, String(isShowing)]) {
            guard isShowing else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            textToTranslate = selectedText
        }
    }

    /// Google Translate's page with the text in the input box, between the View menu's languages.
    private var address: URL {
        var components = URLComponents(string: "https://translate.google.com/")!
        components.queryItems = [
            URLQueryItem(name: "sl", value: direction.source.googleCode),
            URLQueryItem(name: "tl", value: direction.target.googleCode),
            URLQueryItem(name: "text", value: textToTranslate),
            URLQueryItem(name: "op", value: "translate"),
        ]
        return components.url!
    }
}

private struct GoogleTranslateWebView: NSViewRepresentable {
    let address: URL
    let reloadCount: Int
    @Binding var isTyping: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FocusReportingWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = FocusReportingWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = FocusReportingWebView.safariUserAgent
        return webView
    }

    func updateNSView(_ webView: FocusReportingWebView, context: Context) {
        let coordinator = context.coordinator
        webView.reportFocus(to: $isTyping)
        if address != coordinator.loadedAddress || reloadCount != coordinator.reloadCount {
            coordinator.loadedAddress = address
            coordinator.reloadCount = reloadCount
            webView.load(URLRequest(url: address))
        }
    }

    final class Coordinator {
        var loadedAddress: URL?
        var reloadCount = 0
    }
}
