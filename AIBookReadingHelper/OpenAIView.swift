import SwiftUI
import WebKit

/// ChatGPT in the side panel, in place of the selected text and translation. The reader signs in with their own
/// account; the sign-in is kept between launches. Text selected on the page is put into ChatGPT's question box,
/// ready to send.
struct OpenAIView: View {
    static let address = URL(string: "https://chatgpt.com/")!

    /// Opens ChatGPT in the reader's default web browser with the text as the question. Google doesn't allow
    /// signing in inside an app's web view, so a reader who signs in with Google uses ChatGPT there instead.
    static func askInBrowser(_ text: String) {
        var components = URLComponents(url: address, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }

    let selectedText: String
    /// Whether the view is showing. The selection is only put into the question box while it is.
    let isShowing: Bool
    /// Whether the reader is typing in the page, where Space and Esc must type rather than act as shortcuts.
    @Binding var isTyping: Bool
    /// The selection to put in the question box, once it has stopped changing.
    @State private var textToInsert = ""
    @State private var reloadCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OpenAI")
                    .font(.headline)
                Spacer()
                Button("Home", systemImage: "house") {
                    reloadCount += 1
                }
                .labelStyle(.iconOnly)
                .help("Go back to the ChatGPT home page")
                .focusable(false)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            OpenAIWebView(textToInsert: textToInsert, reloadCount: reloadCount, isTyping: $isTyping)
        }
        // Waits for the selection to settle, so dragging across the page doesn't rewrite the question per word.
        .task(id: [selectedText, String(isShowing)]) {
            guard isShowing else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            textToInsert = selectedText
        }
    }
}

private struct OpenAIWebView: NSViewRepresentable {
    let textToInsert: String
    let reloadCount: Int
    @Binding var isTyping: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FocusReportingWebView {
        // The default data store keeps cookies on disk, so the reader stays signed in.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = FocusReportingWebView(frame: .zero, configuration: configuration)
        // Sign-in pages, such as Google's, refuse browsers they don't recognize, so this one presents itself as Safari.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: OpenAIView.address))
        return webView
    }

    func updateNSView(_ webView: FocusReportingWebView, context: Context) {
        let coordinator = context.coordinator
        webView.onFocusChange = { [isTyping = $isTyping] focused in
            DispatchQueue.main.async {
                if isTyping.wrappedValue != focused {
                    isTyping.wrappedValue = focused
                }
            }
        }
        if reloadCount != coordinator.reloadCount {
            coordinator.reloadCount = reloadCount
            webView.load(URLRequest(url: OpenAIView.address))
        }
        if textToInsert != coordinator.insertedText {
            coordinator.insertedText = textToInsert
            coordinator.insert(textToInsert, into: webView)
        }
    }

    final class FocusReportingWebView: WKWebView {
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocusChange?(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocusChange?(false) }
            return resigned
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var insertedText = ""
        var reloadCount = 0
        /// Text that arrived before the page could take it, put in once the page has loaded.
        private var pendingText: String?

        /// Replaces what is in ChatGPT's question box with the text, without sending it.
        /// The box is a rich text editor, so the text is typed in with insertText, which the editor notices,
        /// rather than set directly.
        func insert(_ text: String, into webView: WKWebView) {
            guard !text.isEmpty,
                  let data = try? JSONEncoder().encode(text),
                  let literal = String(data: data, encoding: .utf8) else { return }
            let script = """
            (function (text) {
                var box = document.querySelector('#prompt-textarea') || document.querySelector('textarea');
                if (!box) { return false; }
                box.focus();
                if (box.isContentEditable) {
                    document.execCommand('selectAll', false, null);
                    document.execCommand('insertText', false, text);
                } else {
                    var setValue = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
                    setValue.call(box, text);
                    box.dispatchEvent(new Event('input', { bubbles: true }));
                }
                return true;
            })(\(literal))
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                // The question box isn't there until the page has loaded and the reader has signed in.
                if (result as? Bool) != true {
                    self?.pendingText = text
                } else {
                    self?.pendingText = nil
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let text = pendingText else { return }
            // ChatGPT draws its question box a moment after the page loads.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
                guard let self, let webView, self.pendingText == text else { return }
                self.insert(text, into: webView)
            }
        }

        /// Sign-in pages that open a new window, such as "Continue with Google", open in this view instead.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
