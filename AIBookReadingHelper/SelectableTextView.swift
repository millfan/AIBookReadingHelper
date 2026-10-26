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

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.selection = $selection
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.font = font
        textView.textColor = .labelColor
        guard textView.string != text else { return }
        // Replacing the text moves the selection; that isn't the reader selecting anything.
        context.coordinator.isReplacingText = true
        textView.string = text
        context.coordinator.isReplacingText = false
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
