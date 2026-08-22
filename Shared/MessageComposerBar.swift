//
//  MessageComposerBar.swift
//  SpectRoom
//

import SwiftUI

struct MessageComposerBar: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    var placeholder: String
    var isDisabled: Bool
    var isSending: Bool
    var isRecording: Bool
    var onSend: () -> Void
    var onCamera: () -> Void
    var onRecordingPressChanged: (Bool) -> Void
    var onShortMicTap: () -> Void = {}
    
    @State private var didArmLongPressRecording = false
    @State private var fieldHeight: CGFloat = ComposerTextMetrics.singleLineHeight
    
    /// Hold this long before recording starts (short taps show a tip instead).
    private let micLongPressDuration: Double = 1.0
    
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        HStack(alignment: isSingleLineHeight ? .center : .bottom, spacing: 8) {
            ComposerDismissKeyboardTextView(
                text: $text,
                isFocused: $isFocused,
                placeholder: placeholder,
                isDisabled: isDisabled,
                minHeight: ComposerTextMetrics.singleLineHeight,
                maxHeight: ComposerTextMetrics.threeLineHeight,
                onMeasuredHeightChange: { newHeight in
                    guard abs(fieldHeight - newHeight) > 0.5 else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        fieldHeight = newHeight
                    }
                }
            )
            .padding(.horizontal, 6)
            .frame(height: fieldHeight)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            
            if hasText {
                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Color.green)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending || isDisabled)
            } else {
                Button(action: onCamera) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(SpectRoomTheme.text)
                        .frame(width: 34, height: 34)
                }
                .disabled(isDisabled)
                
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: isRecording ? .regular : .light))
                    .foregroundColor(isRecording ? .red : .primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                    .overlay(
                        Circle()
                            .stroke(isRecording ? Color.red.opacity(0.4) : Color.clear, lineWidth: 2)
                    )
                    .opacity(isDisabled ? 0.5 : 1)
                    .allowsHitTesting(!isDisabled)
                    .onLongPressGesture(
                        minimumDuration: micLongPressDuration,
                        maximumDistance: 60,
                        pressing: { pressing in
                            if pressing {
                                didArmLongPressRecording = false
                            } else if didArmLongPressRecording {
                                // Recording continues in the bottom sheet - stop from there.
                                didArmLongPressRecording = false
                            } else {
                                onShortMicTap()
                            }
                        },
                        perform: {
                            didArmLongPressRecording = true
                            onRecordingPressChanged(true)
                        }
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .opacity(isDisabled ? 0.5 : 1)
        .onChange(of: text) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withAnimation(.easeInOut(duration: 0.15)) {
                    fieldHeight = ComposerTextMetrics.singleLineHeight
                }
            }
        }
    }
    
    private var isSingleLineHeight: Bool {
        fieldHeight <= ComposerTextMetrics.singleLineHeight + 1
    }
}
