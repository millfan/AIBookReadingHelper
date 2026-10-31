import SwiftUI
import WebKit

/// Google Docs in the side panel, for taking notes while reading. Unlike ChatGPT and Google Translate, the selected
/// text isn't put into it. The reader signs in with their own Google account; the sign-in is kept between launches.
struct NotesView: View {
    static let address = URL(string: "https://docs.google.com/")!

    /// Whether the reader is typing in the page, where Space and Esc must type rather than act as shortcuts.
    @Binding var isTyping: Bool
    @State private var reloadCount = 0
    /// For finding why Docs draws blurred: the screen scale the page sees and the window's. Both should be 2 on Retina.
    @State private var scaleReadout = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Text(scaleReadout)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            NotesWebView(reloadCount: reloadCount, isTyping: $isTyping, scaleReadout: $scaleReadout)
        }
    }
}

private struct NotesWebView: NSViewRepresentable {
    let reloadCount: Int
    @Binding var isTyping: Bool
    @Binding var scaleReadout: String

    func makeCoordinator() -> Coordinator {
        Coordinator(scaleReadout: $scaleReadout)
    }

    func makeNSView(context: Context) -> FocusReportingWebView {
        // The default data store keeps cookies on disk, so the reader stays signed in.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Google Docs picks how it draws from the browser it sees, and draws blurred text for the older Safari the
        // other panels name. This one keeps WebKit's own description of this Mac and adds Safari's name and current
        // version, as Safari itself does.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let webView = FocusReportingWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
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

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var reloadCount = 0
        var scaleReadout: Binding<String>

        init(scaleReadout: Binding<String>) {
            self.scaleReadout = scaleReadout
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let windowScale = webView.window?.backingScaleFactor ?? 0
            webView.evaluateJavaScript("window.devicePixelRatio") { [scaleReadout] result, _ in
                let pageScale = (result as? NSNumber)?.doubleValue ?? 0
                scaleReadout.wrappedValue = "page scale \(pageScale.formatted()) · screen \(windowScale.formatted())"
            }
        }

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
