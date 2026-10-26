import AppKit
import SwiftUI

/// Shows text that can be selected but not edited, and reports the part that is selected.
/// SwiftUI's selectable Text can't say what is selected, so this wraps an NSTextView.
struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    @Binding var selection: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> TextScrollView {
        let scrollView = TextScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: TextScrollView, context: Context) {
        context.coordinator.selection = $selection
        let textView = scrollView.textView
        // Setting these on every update would disturb a selection being made.
        if textView.font != font {
            textView.font = font
        }
        if textView.textColor != .labelColor {
            textView.textColor = .labelColor
        }
        guard textView.string != text else { return }
        // Replacing the text moves the selection; that isn't the reader selecting anything.
        context.coordinator.isReplacingText = true
        textView.string = text
        context.coordinator.isReplacingText = false
        scrollView.needsLayout = true
    }

    /// Keeps the text view as wide as the panel and at least as tall, so a click anywhere in it lands on the text.
    /// SwiftUI gives the view its size only after it is made, so a text view sized at creation would be zero by zero:
    /// the text would still draw, but clicks would miss it.
    final class TextScrollView: NSScrollView {
        let textView = NSTextView()

        override func layout() {
            super.layout()
            let size = contentSize
            textView.minSize = NSSize(width: 0, height: size.height)
            if textView.frame.width != size.width {
                textView.setFrameSize(NSSize(width: size.width, height: max(textView.frame.height, size.height)))
            }
            textView.sizeToFit()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var selection: Binding<String>
        var isReplacingText = false

        init(selection: Binding<String>) {
            self.selection = selection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isReplacingText, let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""
            // Reported after the event, so SwiftUI state never changes during a view update.
            DispatchQueue.main.async { [selection] in
                if selection.wrappedValue != selected {
                    selection.wrappedValue = selected
                }
            }
        }
    }
}

extension NSView {
    /// Whether this view, or a view inside it, has the keyboard focus in its window.
    var hasFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }
}
