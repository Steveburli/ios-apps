import SwiftUI
import UIKit
import ThoughtsKit

/// A UITextView that reports Backspace pressed at the very start, which SwiftUI can't see.
final class BlockUITextView: UITextView {
    var onBackspaceAtStart: (() -> Bool)?

    override func deleteBackward() {
        if selectedRange.location == 0, selectedRange.length == 0, let handler = onBackspaceAtStart, handler() {
            return
        }
        super.deleteBackward()
    }
}

/// Fonts for each kind of block, scaled with Dynamic Type.
enum BlockFont {
    static func font(for kind: BlockKind) -> UIFont {
        switch kind {
        case .heading1: return scaled(.systemFont(ofSize: 28, weight: .bold), .title1)
        case .heading2: return scaled(.systemFont(ofSize: 22, weight: .bold), .title2)
        case .heading3: return scaled(.systemFont(ofSize: 19, weight: .semibold), .title3)
        case .code: return scaled(.monospacedSystemFont(ofSize: 14.5, weight: .regular), .body)
        case .quote: return scaled(.systemFont(ofSize: 18, weight: .regular), .body)
        default: return scaled(.systemFont(ofSize: 17, weight: .regular), .body)
        }
    }

    private static func scaled(_ font: UIFont, _ style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    /// The height of one line, for lining up bullets and checkboxes with the text.
    static func lineHeight(for kind: BlockKind) -> CGFloat {
        let font = font(for: kind)
        return ceil(font.lineHeight + lineSpacing(for: kind))
    }

    static func lineSpacing(for kind: BlockKind) -> CGFloat {
        kind.isHeading ? 2 : 4
    }
}

/// One block's editable text.
struct BlockTextView: UIViewRepresentable {
    var text: String
    var kind: BlockKind
    var checked: Bool
    /// When set, this block takes the keyboard with the cursor at this UTF-16 offset.
    var cursorRequest: Int?
    var onRequestHandled: () -> Void
    var onChange: (String) -> Void
    /// Return pressed, with the cursor's UTF-16 offset.
    var onReturn: (Int) -> Void
    /// Backspace at the very start. Return true if it was handled.
    var onBackspaceAtStart: () -> Bool
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BlockUITextView {
        let view = BlockUITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.smartDashesType = .no
        view.adjustsFontForContentSizeCategory = true
        view.keyboardDismissMode = .none
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: BlockUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        view.onBackspaceAtStart = { [weak coordinator] in coordinator?.parent.onBackspaceAtStart() ?? false }
        view.autocorrectionType = kind == .code ? .no : .default
        view.autocapitalizationType = kind == .code ? .none : .sentences
        view.spellCheckingType = kind == .code ? .no : .default

        let styleChanged = coordinator.lastKind != kind || coordinator.lastChecked != checked
        if styleChanged || view.text != text {
            let selection = view.selectedRange
            let attributes = Self.attributes(kind: kind, checked: checked)
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
            view.typingAttributes = attributes
            let length = (text as NSString).length
            if view.isFirstResponder {
                view.selectedRange = NSRange(location: min(selection.location, length),
                                             length: max(0, min(selection.length, length - min(selection.location, length))))
            }
            coordinator.lastKind = kind
            coordinator.lastChecked = checked
        }

        if let offset = cursorRequest {
            coordinator.focus(view, at: offset, attempts: 4)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(size.height), BlockFont.lineHeight(for: kind)))
    }

    static func attributes(kind: BlockKind, checked: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = BlockFont.lineSpacing(for: kind)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: BlockFont.font(for: kind),
            .foregroundColor: Theme.uiInk,
            .paragraphStyle: style,
        ]
        if kind == .todo && checked {
            attributes[.foregroundColor] = Theme.uiMuted
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = Theme.uiMuted
        }
        return attributes
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var lastKind: BlockKind?
        var lastChecked: Bool?
        private var focusToken = 0

        init(_ parent: BlockTextView) {
            self.parent = parent
        }

        /// Takes the keyboard on the next turn of the run loop (the view may not be on screen yet).
        func focus(_ view: BlockUITextView, at offset: Int, attempts: Int) {
            focusToken += 1
            let token = focusToken
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, token == self.focusToken else { return }
                if view.window == nil {
                    if attempts > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.focus(view, at: offset, attempts: attempts - 1)
                        }
                    } else {
                        self.parent.onRequestHandled()
                    }
                    return
                }
                if !view.isFirstResponder { view.becomeFirstResponder() }
                let length = (view.text as NSString).length
                view.selectedRange = NSRange(location: max(0, min(offset, length)), length: 0)
                self.parent.onRequestHandled()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n", !parent.kind.keepsNewlines else { return true }
            if range.length > 0 {
                let remaining = (textView.text as NSString).replacingCharacters(in: range, with: "")
                textView.text = remaining
                parent.onChange(remaining)
            }
            parent.onReturn(range.location)
            return false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }
    }
}
