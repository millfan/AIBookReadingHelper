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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> FocusReportingWebView {
        // The default data store keeps cookies on disk, so the reader stays signed in.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = FocusReportingWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = FocusReportingWebView.safariUserAgent
        webView.uiDelegate = context.coordinator
        // Google Docs draws its text on a canvas sized for the screen it starts on. Loaded before the view is in a
        // window, it takes the screen to be low resolution and draws blurred text on a Retina screen, so it waits.
        webView.whenInWindow = { [weak webView] in
            webView?.load(URLRequest(url: NotesView.address))
        }
        return webView
    }

    func updateNSView(_ webView: FocusReportingWebView, context: Context) {
        webView.reportFocus(to: $isTyping)
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
