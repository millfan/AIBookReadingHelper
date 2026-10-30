import SwiftUI
import WebKit

/// Shows an HTML file or a web page and reports the text selected in it, so it can be translated like text on a captured page.
struct HTMLDocumentView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String
    /// How large to show the page. 1 is the normal size.
    var zoom = PageZoom.normal
    /// Changed to take a picture of the visible page, which is passed to `onSnapshot`.
    var snapshotRequest = 0
    var onSnapshot: ((NSImage) -> Void)? = nil
    /// Called with the address of each page the view goes to, including by following links.
    var onNavigate: ((URL) -> Void)? = nil

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
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.selectedText = $selectedText
        context.coordinator.onNavigate = onNavigate
        if snapshotRequest != context.coordinator.snapshotRequest {
            context.coordinator.snapshotRequest = snapshotRequest
            let onSnapshot = onSnapshot
            webView.takeSnapshot(with: nil) { [weak webView] image, _ in
                guard let image else { return }
                // The page and its address box are hidden behind the picture, so they give up the keyboard.
                // Otherwise they keep taking keys such as Esc, which must go to Back to page.
                webView?.window?.makeFirstResponder(nil)
                onSnapshot?(image)
            }
        }
        if webView.pageZoom != CGFloat(zoom) {
            webView.pageZoom = CGFloat(zoom)
        }
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        if url.isFileURL {
            // The sandbox only grants access to the chosen file, so images and styles next to it may not load.
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
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
        var onNavigate: ((URL) -> Void)?
        var snapshotRequest = 0

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url {
                onNavigate?(url)
            }
        }

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
