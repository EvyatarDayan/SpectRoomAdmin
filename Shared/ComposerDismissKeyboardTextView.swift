//
//  ComposerDismissKeyboardTextView.swift
//  SpectRoom
//
//  Multiline chat field whose keyboard Return key is native "Done".
//  Tapping Done hides the keyboard (does not insert a newline).
//  Height grows with content up to 3 lines (WhatsApp-style).
//

import SwiftUI
import UIKit

enum ComposerTextMetrics {
    private static var bodyLineHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).lineHeight
    }
    
    /// Tighter than a full body+padding slot so the idle field stays compact.
    private static let verticalInsets: CGFloat = 10 // top 5 + bottom 5
    
    static var singleLineHeight: CGFloat {
        ceil(bodyLineHeight + verticalInsets)
    }
    
    static var threeLineHeight: CGFloat {
        ceil(bodyLineHeight * 3 + verticalInsets)
    }
}

struct ComposerDismissKeyboardTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    var placeholder: String
    var isDisabled: Bool = false
    var minHeight: CGFloat = ComposerTextMetrics.singleLineHeight
    var maxHeight: CGFloat = ComposerTextMetrics.threeLineHeight
    var onMeasuredHeightChange: ((CGFloat) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.returnKeyType = .done
        textView.enablesReturnKeyAutomatically = false
        textView.isScrollEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.accessibilityLabel = placeholder
        
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.tag = 9001
        textView.addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 6),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -6),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 5)
        ])
        
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.updatePlaceholderVisibility(for: textView)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        
        if textView.text != text {
            textView.text = text
            context.coordinator.updatePlaceholderVisibility(for: textView)
        }
        
        textView.isEditable = !isDisabled
        textView.isUserInteractionEnabled = !isDisabled
        
        context.coordinator.reportMeasuredHeight(for: textView)
        
        DispatchQueue.main.async {
            if isFocused, !textView.isFirstResponder {
                textView.becomeFirstResponder()
            } else if !isFocused, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }
    
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width.isFinite, width > 0 else {
            return CGSize(width: proposal.width ?? 0, height: context.coordinator.measuredHeight)
        }
        
        let height = context.coordinator.clampedHeight(for: uiView, width: width)
        return CGSize(width: width, height: height)
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerDismissKeyboardTextView
        weak var placeholderLabel: UILabel?
        var measuredHeight: CGFloat
        
        init(_ parent: ComposerDismissKeyboardTextView) {
            self.parent = parent
            self.measuredHeight = parent.minHeight
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updatePlaceholderVisibility(for: textView)
            reportMeasuredHeight(for: textView)
        }
        
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // Native Done key sends "\n" - use it to hide the keyboard.
            if text == "\n" {
                parent.isFocused = false
                textView.resignFirstResponder()
                return false
            }
            return true
        }
        
        func updatePlaceholderVisibility(for textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }
        
        func clampedHeight(for textView: UITextView, width: CGFloat) -> CGFloat {
            let fittingWidth = width > 0 ? width : textView.bounds.width
            guard fittingWidth > 0 else {
                return parent.minHeight
            }
            
            let fitting = textView.sizeThatFits(
                CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
            )
            let height = min(max(fitting.height, parent.minHeight), parent.maxHeight)
            textView.isScrollEnabled = fitting.height > parent.maxHeight + 0.5
            measuredHeight = height
            return height
        }
        
        func reportMeasuredHeight(for textView: UITextView) {
            let width = textView.bounds.width > 0
                ? textView.bounds.width
                : textView.frame.width
            let height = clampedHeight(for: textView, width: width)
            DispatchQueue.main.async {
                self.parent.onMeasuredHeightChange?(height)
            }
        }
    }
}
