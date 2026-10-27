import SwiftUI

/// The Internet view: an address box with the web page below it. Text selected on the page is translated
/// like text on a captured page.
struct WebBrowserView: View {
    @Binding var selectedText: String
    /// Whether the reader is typing in the address box, where Esc must not close the view.
    @Binding var isTypingAddress: Bool
    @AppStorage(SettingsKey.webAddress) private var lastAddress = ""
    @State private var address = ""
    @State private var pageURL: URL?
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                TextField("Type or paste a web address, then press Return", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($isAddressFocused)
                    .onSubmit(openAddress)
            }
            .padding(8)
            Divider()
            if let pageURL {
                HTMLDocumentView(url: pageURL, selectedText: $selectedText) { url in
                    // Following a link on the page shows its address in the box.
                    address = url.absoluteString
                    lastAddress = address
                }
            } else {
                Color(nsColor: .textBackgroundColor)
                    .overlay {
                        Text("Type a web address above and press Return to show the page here.")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .onAppear {
            // Opens the page that was showing last time.
            address = lastAddress
            if address.isEmpty {
                isAddressFocused = true
            } else {
                openAddress()
            }
        }
        .onChange(of: isAddressFocused) {
            isTypingAddress = isAddressFocused
        }
        .onDisappear {
            isTypingAddress = false
        }
    }

    private func openAddress() {
        guard let url = Self.url(from: address) else { return }
        address = url.absoluteString
        lastAddress = address
        pageURL = url
        isAddressFocused = false
    }

    /// The page to open for what was typed: the address itself, "example.com" as https://example.com,
    /// or anything else as a Google search.
    static func url(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://"), let url = URL(string: text) {
            return url
        }
        if text.contains("."), !text.contains(" "), let url = URL(string: "https://" + text) {
            return url
        }
        var search = URLComponents(string: "https://www.google.com/search")
        search?.queryItems = [URLQueryItem(name: "q", value: text)]
        return search?.url
    }
}
