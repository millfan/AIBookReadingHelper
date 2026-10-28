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
