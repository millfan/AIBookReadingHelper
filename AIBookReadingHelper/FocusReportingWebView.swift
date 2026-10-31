import SwiftUI
import WebKit

/// A web view that says when the reader starts and stops typing in it, so Space and Esc can type there rather than act
/// as shortcuts.
final class FocusReportingWebView: WKWebView {
    /// Sign-in pages, such as Google's, refuse browsers they don't recognize, so the side panel's pages present
    /// themselves as Safari.
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

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

    /// Keeps `isTyping` set while the web view has focus.
    func reportFocus(to isTyping: Binding<Bool>) {
        onFocusChange = { focused in
            DispatchQueue.main.async {
                if isTyping.wrappedValue != focused {
                    isTyping.wrappedValue = focused
                }
            }
        }
    }
}

extension WKWebViewConfiguration {
    /// Names the browser as the Safari installed on this Mac, added to WebKit's own description as Safari itself does,
    /// so Google Docs doesn't call it unsupported. Should Docs still show its banner saying the browser is no longer
    /// supported, though it works, it is hidden.
    func presentAsInstalledSafari() {
        applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        userContentController.addUserScript(WKUserScript(source: Self.hideUnsupportedBrowserBanner,
                                                         injectionTime: .atDocumentEnd,
                                                         forMainFrameOnly: true))
    }

    /// The version of Safari installed on this Mac.
    fileprivate static let safariVersion = Bundle(path: "/Applications/Safari.app")?
        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "26.0"

    /// Hides Google Docs' banner saying the browser is no longer supported, the smallest block around its message,
    /// whenever Docs shows it.
    fileprivate static let hideUnsupportedBrowserBanner = """
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
}
