//
//  HelpSupportView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-11-16.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppStateManager

    enum Topic: String, CaseIterable, Identifiable {
        case safety, bug, feedback, accountFreeze, accountBan, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .bug:
                return "support.topic.bug".localized
            case .safety:
                return "support.topic.safety".localized
            case .feedback:
                return "support.topic.feedback".localized
            case .accountFreeze:
                return localizedOrFallback("support.topic.account.freeze", "Account freeze")
            case .accountBan:
                return localizedOrFallback("support.topic.account.ban", "Account ban")
            case .other:
                return "support.topic.other".localized
            }
        }

        private static func localizedOrFallback(_ key: String, _ fallback: String) -> String {
            let value = key.localized
            return (value == key || value.isEmpty) ? fallback : value
        }

        private func localizedOrFallback(_ key: String, _ fallback: String) -> String {
            Self.localizedOrFallback(key, fallback)
        }

        var subjectPrefix: String {
            switch self {
            case .bug:           return "[Bug]"
            case .safety:        return "[Safety]"
            case .feedback:      return "[Feedback]"
            case .accountFreeze: return "[Account freeze]"
            case .accountBan:    return "[Account ban]"
            case .other:         return "[Other]"
            }
        }

        /// Moderation topics are only offered when the sheet is opened from freeze/ban flows.
        var isModerationOnly: Bool {
            switch self {
            case .accountFreeze, .accountBan: return true
            default: return false
            }
        }
    }

    /// Topics shown in the chip row. Moderation topics only appear when preselected/locked.
    private var selectableTopics: [Topic] {
        if let lockedTopic {
            return [lockedTopic]
        }
        return Topic.allCases.filter { !$0.isModerationOnly }
    }

    var initialTopic: Topic = .safety
    var lockedTopic: Topic? = nil
    var maxMessageLength: Int = 500
    var onMessageSent: (() -> Void)? = nil

    @State private var selectedTopic: Topic
    @State private var message: String = ""
    @State private var isSending = false
    @State private var didSendSuccessfully = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var didAttemptSend = false

    init(
        initialTopic: Topic = .safety,
        lockedTopic: Topic? = nil,
        maxMessageLength: Int = 500,
        onMessageSent: (() -> Void)? = nil
    ) {
        self.initialTopic = initialTopic
        self.lockedTopic = lockedTopic
        self.maxMessageLength = maxMessageLength
        self.onMessageSent = onMessageSent
        _selectedTopic = State(initialValue: lockedTopic ?? initialTopic)
    }

    private var showMinWarning: Bool {
        didAttemptSend && !didSendSuccessfully && message.trimmingCharacters(in: .whitespacesAndNewlines).count < 20
    }

    var body: some View {
        NavigationView {
            ZStack {
                SpectRoomBackground()

                VStack(alignment: .leading, spacing: 24) {
                        VStack(spacing: 16) {
                            Text("support.title".localized)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(SpectRoomTheme.text)
                                .multilineTextAlignment(.center)

                            Text("support.subtitle".localized)
                                .font(.body)
                                .foregroundColor(SpectRoomTheme.text.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)

                        // Topic chips
                        VStack(alignment: .leading, spacing: 8) {
                            Text("support.topic.label".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)

                            HStack(spacing: 10) {
                                ForEach(selectableTopics) { topic in
                                    let isSelected = topic == selectedTopic
                                    Button {
                                        guard lockedTopic == nil else { return }
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if didSendSuccessfully {
                                                message = ""
                                                didSendSuccessfully = false
                                                didAttemptSend = false
                                            }
                                            selectedTopic = topic
                                        }
                                    } label: {
                                        Text(topic.label)
                                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .foregroundColor(isSelected ? .white : SpectRoomTheme.text)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.blue : SpectRoomTheme.card)
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.clear : SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(lockedTopic != nil)
                                }
                            }
                        }

                        // Message field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("support.message.label".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)

                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("support.message.placeholder".localized)
                                        .foregroundColor(Color.gray.opacity(0.6))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                }
                                TextEditor(text: $message)
                                    .frame(height: 140)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.sentences)
                                    .disabled(didSendSuccessfully)
                                    .opacity(didSendSuccessfully ? 0.5 : 1)
                                    .onChange(of: message) { _, newValue in
                                        if newValue.count > maxMessageLength {
                                            message = String(newValue.prefix(maxMessageLength))
                                        }
                                    }
                            }
                            .background(SpectRoomTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        showMinWarning ? Color.red : Color.gray.opacity(0.25),
                                        lineWidth: showMinWarning ? 1.5 : 1
                                    )
                            )

                            HStack {
                                Text(showMinWarning ? "support.message.min.chars".localized : " ")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                                    .opacity(showMinWarning ? 1 : 0)
                                Spacer()
                                Text("\(message.count) / \(maxMessageLength)")
                                    .font(.system(size: 12))
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                            }
                            .padding(.top, 2)
                        }

                        // Send button
                        Button(action: send) {
                            Group {
                                if isSending {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(didSendSuccessfully ? "support.button.sent".localized : "support.button.send".localized)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(didSendSuccessfully ? Color.green : Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isSending || didSendSuccessfully)

                        // OR divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            Text("support.or".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        // Email row
                        Button {
                            openMail(to: "spectroom.support@gmail.com")
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("✉️")
                                        .font(.system(size: 18))
                                    Text("support.email.label".localized)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(SpectRoomTheme.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(SpectRoomTheme.secondaryText)
                                }
                                Text("spectroom.support@gmail.com")
                                    .font(.system(size: 14))
                                    .foregroundColor(.blue)
                                    .padding(.leading, 30)
                            }
                            .padding(14)
                            .background(SpectRoomTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("support.nav.title".localized)
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.close".localized) { dismiss() }
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .presentationDetents([.large])
    }
}

// MARK: - Actions
private extension HelpSupportView {
    func send() {
        didAttemptSend = true
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return }

        isSending = true

        Task {
            let authUser = Auth.auth().currentUser
            var userId = appState.currentUser?.firebaseDocumentId
                ?? authUser?.uid
                ?? appState.currentUser?.id.uuidString
                ?? ""
            var userName = (appState.currentUser?.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var userEmail = (appState.currentUser?.email ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let authUser {
                if userId.isEmpty || userId.lowercased() == "unknown" {
                    userId = authUser.uid
                }
                if userEmail.isEmpty, let email = authUser.email {
                    userEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if SupportTicket.isPlaceholderName(userName),
                   let displayName = authUser.displayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !SupportTicket.isPlaceholderName(displayName) {
                    userName = displayName
                }
            }

            if !userId.isEmpty,
               let snap = try? await Firestore.firestore().collection("users").document(userId).getDocument(),
               let data = snap.data() {
                if SupportTicket.isPlaceholderName(userName),
                   let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !SupportTicket.isPlaceholderName(name) {
                    userName = name
                }
                if userEmail.isEmpty || !userEmail.contains("@"),
                   let email = (data["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   email.contains("@") {
                    userEmail = email
                }
            }

            if SupportTicket.isPlaceholderName(userName) {
                userName = "Unknown"
            }

            let ticketId = SupportTicket.makeSupportTicketId()

            let data: [String: Any] = [
                "ticketId": ticketId,
                "ticketNumber": ticketId,
                "userId": userId.isEmpty ? "unknown" : userId,
                "userName": userName,
                "userEmail": userEmail,
                "topic": selectedTopic.label,
                "message": trimmed,
                "status": "new",
                "createdAt": FieldValue.serverTimestamp()
            ]

            do {
                try await Firestore.firestore().collection("supportMessages").addDocument(data: data)
                await MainActor.run {
                    isSending = false
                    didSendSuccessfully = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onMessageSent?()
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    func openMail(to address: String) {
        if let url = URL(string: "mailto:\(address)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    HelpSupportView()
        .environmentObject(AppStateManager.shared)
}
