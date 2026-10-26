import SwiftUI
import VisionKit

/// Shows a captured page with Apple's Live Text on top, so words, phrases and sentences can be selected by dragging.
struct LiveTextImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var selectedText: String
    @Binding var isAnalyzing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText, isAnalyzing: $isAnalyzing)
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        // Without these, the photo's pixel size becomes the view's size and it won't fit the space it is given.
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            imageView.setContentHuggingPriority(.defaultLow, for: orientation)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: orientation)
        }

        let overlayView = context.coordinator.overlayView
        overlayView.frame = imageView.bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.trackingImageView = imageView
        overlayView.preferredInteractionTypes = .textSelection
        overlayView.delegate = context.coordinator
        imageView.addSubview(overlayView)
        return imageView
    }

    /// Takes exactly the space SwiftUI offers, whatever the size of the photo.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        context.coordinator.selectedText = $selectedText
        context.coordinator.isAnalyzing = $isAnalyzing
        guard imageView.image !== image else { return }
        imageView.image = image
        context.coordinator.analyze(image)
    }

    @MainActor
    final class Coordinator: NSObject, ImageAnalysisOverlayViewDelegate {
        let overlayView = ImageAnalysisOverlayView()
        var selectedText: Binding<String>
        var isAnalyzing: Binding<Bool>
        private let analyzer = ImageAnalyzer()
        private var analysisTask: Task<Void, Never>?

        init(selectedText: Binding<String>, isAnalyzing: Binding<Bool>) {
            self.selectedText = selectedText
            self.isAnalyzing = isAnalyzing
        }

        func analyze(_ image: NSImage) {
            analysisTask?.cancel()
            overlayView.analysis = nil
            analysisTask = Task {
                // Bindings are updated inside the task so SwiftUI state never changes during a view update.
                selectedText.wrappedValue = ""
                isAnalyzing.wrappedValue = true
                let configuration = ImageAnalyzer.Configuration([.text])
                let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: configuration)
                guard !Task.isCancelled else { return }
                overlayView.analysis = analysis
                isAnalyzing.wrappedValue = false
            }
        }

        nonisolated func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) {
            MainActor.assumeIsolated {
                // Keep the last selection when something else, such as the side panel, took the focus,
                // so only a click on the page clears it.
                if overlayView.selectedText.isEmpty, !overlayView.hasFocus, !isAnalyzing.wrappedValue {
                    return
                }
                selectedText.wrappedValue = overlayView.selectedText
            }
        }
    }
}
