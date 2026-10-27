import AppKit
import SwiftUI

/// Shows text that can be selected, and optionally edited, and reports the part that is selected.
/// SwiftUI's selectable Text can't say what is selected, so this wraps an NSTextView.
struct SelectableTextView: NSViewRepresentable {
    let content: NSAttributedString
    @Binding var selection: String
    /// Set for editable text: what the reader types or pastes is written back here.
    private var editedText: Binding<String>?
    /// Set for editable text: whether the reader is typing in it.
    private var isFocused: Binding<Bool>?
    private var font: NSFont?

    init(text: String, font: NSFont, selection: Binding<String>) {
        content = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        _selection = selection
        self.font = font
    }

    /// Plain text the reader can also type into or paste into.
    init(editing text: Binding<String>, font: NSFont, selection: Binding<String>, isFocused: Binding<Bool>) {
        self.init(text: text.wrappedValue, font: font, selection: selection)
        editedText = text
        self.isFocused = isFocused
    }

    /// Rich text, such as a laid-out dictionary definition.
    init(attributedText: NSAttributedString, selection: Binding<String> = .constant("")) {
        content = attributedText
        _selection = selection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> TextScrollView {
        let scrollView = TextScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.textView
        textView.isEditable = editedText != nil
        textView.isSelectable = true
        textView.allowsUndo = true
        if let font {
            // Typed and pasted text gets the same font; pasted text loses its own styling.
            textView.font = font
            textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        }
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.focusChanged(focused)
        }
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
        context.coordinator.editedText = editedText
        context.coordinator.isFocused = isFocused
        let textView = scrollView.textView
        // Replacing the text on every update would disturb a selection being made, or typing.
        // Compared with what was last set, since the text view adjusts the attributes it is given,
        // and with what is showing, which already includes what the reader typed.
        guard let storage = textView.textStorage, context.coordinator.content?.isEqual(to: content) != true,
              textView.string != content.string || editedText == nil else { return }
        context.coordinator.content = content
        // Replacing the text moves the selection; that isn't the reader selecting anything.
        context.coordinator.isReplacingText = true
        storage.setAttributedString(content)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        context.coordinator.isReplacingText = false
        scrollView.needsLayout = true
    }

    /// Keeps the text view as wide as the panel and at least as tall, so a click anywhere in it lands on the text.
    /// SwiftUI gives the view its size only after it is made, so a text view sized at creation would be zero by zero:
    /// the text would still draw, but clicks would miss it.
    final class TextScrollView: NSScrollView {
        let textView = FocusReportingTextView()

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

    /// A text view that says when it gains or loses the keyboard focus.
    final class FocusReportingTextView: NSTextView {
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
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var selection: Binding<String>
        var editedText: Binding<String>?
        var isFocused: Binding<Bool>?
        var isReplacingText = false
        var content: NSAttributedString?

        init(selection: Binding<String>) {
            self.selection = selection
        }

        func focusChanged(_ focused: Bool) {
            DispatchQueue.main.async { [isFocused] in
                if isFocused?.wrappedValue != focused {
                    isFocused?.wrappedValue = focused
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isReplacingText, let textView = notification.object as? NSTextView else { return }
            editedText?.wrappedValue = textView.string
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
