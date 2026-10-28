import PDFKit
import SwiftUI

/// Shows a PDF file and reports the text selected in it, so it can be translated like text on a captured page.
/// Only PDFs with real text can be selected; a scan of pictures has no text to pick.
struct PDFDocumentView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String
    /// How large to show the pages, compared with fitting the page to the view. 1 fits the page.
    var zoom = PageZoom.normal

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
        if pdfView.document?.documentURL != url {
            context.coordinator.lastSelection = nil
            pdfView.document = PDFDocument(url: url)
        }
        // Only when the zoom changes, so a pinch on the trackpad isn't undone by the next selection.
        if context.coordinator.appliedZoom != zoom {
            context.coordinator.appliedZoom = zoom
            if zoom == PageZoom.normal {
                // The page fits the view as the view changes size.
                pdfView.autoScales = true
            } else {
                // Scaled from the size that fits the page, once the view has been laid out and has that size.
                DispatchQueue.main.async {
                    let fit = pdfView.scaleFactorForSizeToFit
                    guard fit > 0 else { return }
                    pdfView.autoScales = false
                    pdfView.scaleFactor = fit * CGFloat(zoom)
                }
            }
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectedText: Binding<String>
        private var observer: NSObjectProtocol?
        /// The zoom the pages were last shown at.
        var appliedZoom: Double?
        /// The last non-empty selection, put back when the PDF loses its selection by losing the focus.
        var lastSelection: PDFSelection?

        init(selectedText: Binding<String>) {
            self.selectedText = selectedText
        }

        func startObserving(_ pdfView: PDFView) {
            observer = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged,
                                                              object: pdfView,
                                                              queue: .main) { [weak self, weak pdfView] _ in
                MainActor.assumeIsolated {
                    guard let self, let pdfView else { return }
                    self.selectionChanged(in: pdfView)
                }
            }
        }

        private func selectionChanged(in pdfView: PDFView) {
            let text = pdfView.currentSelection?.string ?? ""
            // If the selection went away because something else, such as the side panel, took the focus,
            // put it back, so only a click inside the PDF clears it.
            if text.isEmpty, !pdfView.hasFocus, let lastSelection {
                pdfView.setCurrentSelection(lastSelection, animate: false)
                return
            }
            if !text.isEmpty {
                lastSelection = pdfView.currentSelection
            }
            selectedText.wrappedValue = text
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }
    }
}
