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
        return WKWebView(frame: .zero, configuration: configuration)
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
        /// Sends the page's selection to the app every time it changes.
        static let selectionScript = """
        document.addEventListener('selectionchange', function () {
            window.webkit.messageHandlers.\(messageName).postMessage(String(window.getSelection()));
        });
        """

        var selectedText: Binding<String>
        var loadedURL: URL?

        init(selectedText: Binding<String>) {
            self.selectedText = selectedText
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            selectedText.wrappedValue = message.body as? String ?? ""
        }
    }
}
