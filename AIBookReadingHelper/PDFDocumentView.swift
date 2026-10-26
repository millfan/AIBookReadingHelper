import PDFKit
import SwiftUI

/// Shows a PDF file and reports the text selected in it, so it can be translated like text on a captured page.
/// Only PDFs with real text can be selected; a scan of pictures has no text to pick.
struct PDFDocumentView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        context.coordinator.startObserving(pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.selectedText = $selectedText
        guard pdfView.document?.documentURL != url else { return }
        pdfView.document = PDFDocument(url: url)
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectedText: Binding<String>
        private var observer: NSObjectProtocol?

        init(selectedText: Binding<String>) {
            self.selectedText = selectedText
        }

        func startObserving(_ pdfView: PDFView) {
            observer = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged,
                                                              object: pdfView,
                                                              queue: .main) { [weak self, weak pdfView] _ in
                MainActor.assumeIsolated {
                    self?.selectedText.wrappedValue = pdfView?.currentSelection?.string ?? ""
                }
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }
    }
}
