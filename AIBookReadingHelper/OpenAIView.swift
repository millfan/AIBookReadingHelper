import SwiftUI
import WebKit

/// ChatGPT in the side panel, in place of the selected text and translation. The reader signs in with their own
/// account; the sign-in is kept between launches. Text selected on the page is put into ChatGPT's question box,
/// ready to send.
struct OpenAIView: View {
    static let address = URL(string: "https://chatgpt.com/")!

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
            // A whole number of points tall, so the page below starts on a pixel. Text sets a fractional height,
            // which put the page partway through a pixel and blurred Google Docs, which draws its text on a canvas.
            .frame(height: 36)
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
        webView.customUserAgent = FocusReportingWebView.safariUserAgent
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: OpenAIView.address))
        return webView
    }

    func updateNSView(_ webView: FocusReportingWebView, context: Context) {
        let coordinator = context.coordinator
        webView.reportFocus(to: $isTyping)
        if reloadCount != coordinator.reloadCount {
            coordinator.reloadCount = reloadCount
            webView.load(URLRequest(url: OpenAIView.address))
        }
        if textToInsert != coordinator.insertedText {
            coordinator.insertedText = textToInsert
            coordinator.insert(textToInsert, into: webView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var insertedText = ""
        var reloadCount = 0
        /// Text that arrived before the page could take it, put in once the page has loaded.
        private var pendingText: String?

        /// Replaces what is in ChatGPT's question box with the text, without sending it.
        /// The box is a rich text editor that only takes text it sees typed or pasted, so the text is typed in with
        /// insertText, then pasted, then written in directly, until the box shows it. The script waits a few seconds
        /// for the box, which ChatGPT draws a moment after the page loads.
        func insert(_ text: String, into webView: WKWebView) {
            guard !text.isEmpty else { return }
            pendingText = text
            let script = """
            const findBox = () =>
                document.querySelector('#prompt-textarea[contenteditable="true"]') ||
                document.querySelector('[contenteditable="true"].ProseMirror') ||
                document.querySelector('#prompt-textarea') ||
                document.querySelector('form textarea:not([hidden]):not([disabled])');
            for (let i = 0; i < 40 && !findBox(); i++) {
                await new Promise(resolve => setTimeout(resolve, 250));
            }
            const box = findBox();
            if (!box) { return false; }
            const normalize = s => (s || '').replace(/\\s+/g, ' ').trim();
            const wanted = normalize(text);
            const shows = () => normalize(box.isContentEditable ? box.innerText : box.value) === wanted;
            box.focus();
            if (!box.isContentEditable) {
                const setValue = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
                setValue.call(box, text);
                box.dispatchEvent(new Event('input', { bubbles: true }));
                return shows();
            }
            const selectAll = () => {
                const range = document.createRange();
                range.selectNodeContents(box);
                const selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(range);
            };
            selectAll();
            document.execCommand('insertText', false, text);
            if (!shows()) {
                selectAll();
                const data = new DataTransfer();
                data.setData('text/plain', text);
                box.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
            }
            if (!shows()) {
                box.replaceChildren(...text.split('\\n').map(line => {
                    const paragraph = document.createElement('p');
                    paragraph.textContent = line;
                    return paragraph;
                }));
                box.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
            }
            return shows();
            """
            webView.callAsyncJavaScript(script, arguments: ["text": text], in: nil, in: .page) { [weak self] result in
                guard let self, self.pendingText == text else { return }
                // The question box isn't there until the reader has signed in, so a failed try waits for the next page.
                if case .success(let shown) = result, (shown as? Bool) == true {
                    self.pendingText = nil
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
