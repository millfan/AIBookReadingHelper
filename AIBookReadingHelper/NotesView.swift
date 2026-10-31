import SwiftUI
import WebKit

/// Google Docs in the side panel, for taking notes while reading. Unlike ChatGPT and Google Translate, the selected
/// text isn't put into it. The reader signs in with their own Google account; the sign-in is kept between launches.
struct NotesView: View {
    static let address = URL(string: "https://docs.google.com/")!

    /// Whether the reader is typing in the page, where Space and Esc must type rather than act as shortcuts.
    @Binding var isTyping: Bool
    @State private var reloadCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                Button("Home", systemImage: "house") {
                    reloadCount += 1
                }
                .labelStyle(.iconOnly)
                .help("Go back to the Google Docs home page")
                .focusable(false)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
            NotesWebView(reloadCount: reloadCount, isTyping: $isTyping)
        }
    }
}

private struct NotesWebView: NSViewRepresentable {
    let reloadCount: Int
    @Binding var isTyping: Bool
    /// The size set with Cmd+ and Cmd−, shared with the File and Internet views.
    @AppStorage(SettingsKey.pageZoom) private var zoom = PageZoom.normal

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FocusReportingWebView {
        // The default data store keeps cookies on disk, so the reader stays signed in.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(source: Self.hideUnsupportedBrowserBanner,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true))
        // Google Docs warns that the browser is unsupported unless it is named as Safari. This adds the name and
        // version of the Safari on this Mac to WebKit's own description, as Safari itself does.
        configuration.applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        let webView = FocusReportingWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: NotesView.address))
        return webView
    }

    /// The version of Safari installed on this Mac.
    static let safariVersion = Bundle(path: "/Applications/Safari.app")?
        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "26.0"

    /// Should Google Docs still say the browser is no longer supported, though it works, this hides that banner, the
    /// smallest block around its message, whenever Docs shows it.
    static let hideUnsupportedBrowserBanner = """
    (function () {
        var message = 'browser version is no longer supported';
        function hideBanner() {
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            var node;
            while ((node = walker.nextNode())) {
                if (node.nodeValue.indexOf(message) === -1) { continue; }
                var banner = node.parentElement;
                while (banner.parentElement && banner.parentElement !== document.body &&
                       banner.parentElement.innerText.trim().length < 300) {
                    banner = banner.parentElement;
                }
                banner.style.display = 'none';
            }
        }
        hideBanner();
        var pending = false;
        new MutationObserver(function () {
            if (pending) { return; }
            pending = true;
            setTimeout(function () { pending = false; hideBanner(); }, 300);
        }).observe(document.body, { childList: true, subtree: true });
    })();
    """

    func updateNSView(_ webView: FocusReportingWebView, context: Context) {
        webView.reportFocus(to: $isTyping)
        if webView.pageZoom != CGFloat(zoom) {
            webView.pageZoom = CGFloat(zoom)
        }
        if reloadCount != context.coordinator.reloadCount {
            context.coordinator.reloadCount = reloadCount
            webView.load(URLRequest(url: NotesView.address))
        }
    }

    final class Coordinator: NSObject, WKUIDelegate {
        var reloadCount = 0

        /// Documents that Google Docs opens in a new tab, such as a new blank document, open in this view instead.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
