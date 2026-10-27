import SwiftUI
import WebKit

/// Shows an HTML file and reports the text selected in it, so it can be translated like text on a captured page.
struct HTMLDocumentView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(source: Coordinator.selectionScript,
                                                     injectionTime: .atDocumentEnd,
                                                     forMainFrameOnly: true))
        contentController.add(context.coordinator, name: Coordinator.messageName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.selectedText = $selectedText
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        // The sandbox only grants access to the chosen file, so images and styles next to it may not load.
        webView.loadFileURL(url, allowingReadAccessTo: url)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let messageName = "selection"
        /// Sends the page's selection to the app every time it changes, and remembers it so it can be put back.
        static let selectionScript = """
        var lastSelectedRange = null;
        document.addEventListener('selectionchange', function () {
            var selection = window.getSelection();
            if (selection.rangeCount > 0 && !selection.isCollapsed) {
                lastSelectedRange = selection.getRangeAt(0).cloneRange();
            }
            window.webkit.messageHandlers.\(messageName).postMessage(String(selection));
        });
        function restoreSelection() {
            if (lastSelectedRange) {
                var selection = window.getSelection();
                selection.removeAllRanges();
                selection.addRange(lastSelectedRange);
            }
        }
        """

        var selectedText: Binding<String>
        var loadedURL: URL?
        weak var webView: WKWebView?

        init(selectedText: Binding<String>) {
            self.selectedText = selectedText
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let text = message.body as? String ?? ""
            // The page drops its selection when something else, such as the side panel, takes the focus.
            // Put it back, so only a click inside the page clears it.
            if text.isEmpty, let webView, !webView.hasFocus {
                webView.evaluateJavaScript("restoreSelection()")
                return
            }
            selectedText.wrappedValue = text
        }
    }
}
