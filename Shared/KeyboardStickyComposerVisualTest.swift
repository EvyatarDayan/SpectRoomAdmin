//
//  KeyboardStickyComposerVisualTest.swift
//  SpectRoom
//
//  Launch with argument: -KeyboardComposerVisualTest
//

import SwiftUI

struct KeyboardStickyComposerVisualTest: View {
    @State private var text = ""
    @State private var showConversation = true
    @State private var phaseLabel = "KB Closed"
    @State private var keyboardScrollToken = 0
    @FocusState private var focused: Bool
    
    private let bottomAnchorID = "visual-test-bottom"
    
    var body: some View {
        Color.blue.opacity(0.15)
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $showConversation) {
                conversationScreen
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    phaseLabel = "KB Open"
                    focused = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    phaseLabel = "KB Closed"
                    focused = false
                }
            }
    }
    
    private var conversationScreen: some View {
        NavigationStack {
            messagesScroll
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                        .background {
                            Color(.systemGray2)
                                .ignoresSafeArea(edges: .bottom)
                        }
                }
                .background {
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.75, blue: 0.95),
                            Color(red: 0.70, green: 0.88, blue: 0.70),
                            Color(red: 0.98, green: 0.85, blue: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                .navigationTitle("Visual Test")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showConversation = false
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(phaseLabel)
                            .font(.caption)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                }
        }
    }
    
    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<8, id: \.self) { index in
                        HStack {
                            Spacer()
                            Text("Sample message \(index + 1)")
                                .padding(12)
                                .background(Color.blue.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchorID)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: keyboardScrollToken) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: focused) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                keyboardScrollToken += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                keyboardScrollToken += 1
            }
        }
    }
    
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 38)
                .frame(minWidth: 0, maxWidth: .infinity)
                .layoutPriority(1)
                .background(SpectRoomTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            
            Image(systemName: "folder").frame(width: 34, height: 34)
            Image(systemName: "mic").frame(width: 34, height: 34)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
}
