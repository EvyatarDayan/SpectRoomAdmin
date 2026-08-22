import Foundation
import UIKit
import AVFoundation

struct MessagesExportConversation {
    let partnerName: String
    let messages: [MessageDisplay]
}

enum MessagesExport {
    /// Short enough to stay on one line on phone screens when viewing the export.
    private static let divider = String(repeating: "─", count: 28)
    
    static func writePDFFile(
        currentUserName: String,
        currentUserId: String,
        conversations: [MessagesExportConversation]
    ) async throws -> URL {
        let dateStamp = fileDateFormatter.string(from: Date())
        let fileName = "SpectRoom-Messages-\(dateStamp).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        let bodyFont = UIFont.systemFont(ofSize: 14)
        let boldFont = UIFont.boldSystemFont(ofSize: 14)
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let headerFont = UIFont.boldSystemFont(ofSize: 16)
        
        let regular: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]
        let bold: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .foregroundColor: UIColor.black
        ]
        let title: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        let header: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.systemBlue
        ]
        
        // Wrapped lines indent to align under the text after "• ".
        let bulletIndent = ("• " as NSString).size(withAttributes: [.font: bodyFont]).width
        let bulletParagraph = NSMutableParagraphStyle()
        bulletParagraph.firstLineHeadIndent = 0
        bulletParagraph.headIndent = bulletIndent
        let bullet: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: bulletParagraph
        ]
        
        let document = NSMutableAttributedString()
        
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any] = regular) {
            document.append(NSAttributedString(string: string, attributes: attributes))
        }
        
        append("settings.export.messages.file.title".localized + "\n", title)
        append(String(
            format: "settings.export.messages.exported.at".localized,
            exportedAtFormatter.string(from: Date())
        ) + "\n")
        append(String(
            format: "settings.export.messages.account".localized,
            currentUserName
        ) + "\n\n")
        
        if conversations.isEmpty {
            append("settings.export.messages.empty".localized)
        } else {
            for (index, conversation) in conversations.enumerated() {
                if index > 0 {
                    append("\n")
                }
                append(divider + "\n")
                append(
                    String(
                        format: "settings.export.messages.conversation.with".localized,
                        conversation.partnerName
                    ) + "\n",
                    header
                )
                append(divider + "\n\n")
                
                let messages = await enrichVoiceDurations(conversation.messages)
                var lastDayKey: String?
                for group in groupedMessages(messages, currentUserId: currentUserId) {
                    if lastDayKey != group.dayKey {
                        if lastDayKey != nil {
                            append("\n")
                        }
                        append("--- \(group.dayLabel) ---\n\n", bold)
                        lastDayKey = group.dayKey
                    }
                    
                    append("[\(group.timestamp)]", bold)
                    append(" \(group.sender):\n")
                    for body in group.bodies {
                        append("• \(body)\n", bullet)
                    }
                    append("\n")
                }
            }
        }
        
        let data = renderPDF(from: document)
        try data.write(to: url, options: .atomic)
        return url
    }
    
    /// US Letter pages with margins; paginates via TextKit layout.
    private static func renderPDF(from attributedString: NSAttributedString) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let textBounds = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - margin * 2,
            height: pageHeight - margin * 2
        )
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            let textStorage = NSTextStorage(attributedString: attributedString)
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            
            var done = false
            while !done {
                context.beginPage()
                
                let textContainer = NSTextContainer(size: textBounds.size)
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)
                
                let glyphRange = layoutManager.glyphRange(for: textContainer)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: textBounds.origin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textBounds.origin)
                
                if glyphRange.length == 0 {
                    done = true
                } else {
                    done = NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs
                }
            }
        }
    }
    
    private struct ExportMessageGroup {
        let dayKey: String
        let dayLabel: String
        let timestamp: String
        let senderId: String
        let sender: String
        var bodies: [String]
    }
    
    /// When Firestore has 0/missing duration, read it from the audio file (same as chat UI).
    private static func enrichVoiceDurations(_ messages: [MessageDisplay]) async -> [MessageDisplay] {
        await withTaskGroup(of: (Int, MessageDisplay).self) { group in
            for (index, message) in messages.enumerated() {
                group.addTask {
                    guard message.messageType == .voice else {
                        return (index, message)
                    }
                    if let duration = message.voiceDuration, duration >= 0.5 {
                        return (index, message)
                    }
                    guard let audioURL = URL(string: message.content) else {
                        return (index, message)
                    }
                    let resolved = await audioDuration(from: audioURL) ?? message.voiceDuration
                    guard let resolved, resolved > 0 else {
                        return (index, message)
                    }
                    let updated = MessageDisplay(
                        id: message.id,
                        content: message.content,
                        messageType: message.messageType,
                        senderName: message.senderName,
                        recipientName: message.recipientName,
                        senderId: message.senderId,
                        recipientId: message.recipientId,
                        createdAt: message.createdAt,
                        isRead: message.isRead,
                        senderProfilePhotoURL: message.senderProfilePhotoURL,
                        recipientProfilePhotoURL: message.recipientProfilePhotoURL,
                        voiceDuration: resolved
                    )
                    return (index, updated)
                }
            }
            
            var enriched = messages
            for await (index, message) in group {
                enriched[index] = message
            }
            return enriched
        }
    }
    
    private static func audioDuration(from url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        do {
            let time = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }
    
    /// Consecutive messages from the same person in the same minute share one header.
    private static func groupedMessages(
        _ messages: [MessageDisplay],
        currentUserId: String
    ) -> [ExportMessageGroup] {
        var groups: [ExportMessageGroup] = []
        
        for message in messages {
            let isOutgoing = message.senderId == currentUserId || message.senderName == "You"
            let senderId = isOutgoing ? currentUserId : message.senderId
            let sender = isOutgoing
                ? "settings.export.messages.you".localized
                : message.senderName
            let dayKey = dayKeyFormatter.string(from: message.createdAt)
            let dayLabel = dayHeaderFormatter.string(from: message.createdAt)
            let timestamp = messageTimeFormatter.string(from: message.createdAt)
            let body = bodyText(for: message)
            
            if let lastIndex = groups.indices.last,
               groups[lastIndex].dayKey == dayKey,
               groups[lastIndex].timestamp == timestamp,
               groups[lastIndex].senderId == senderId {
                groups[lastIndex].bodies.append(body)
            } else {
                groups.append(
                    ExportMessageGroup(
                        dayKey: dayKey,
                        dayLabel: dayLabel,
                        timestamp: timestamp,
                        senderId: senderId,
                        sender: sender,
                        bodies: [body]
                    )
                )
            }
        }
        
        return groups
    }
    
    private static func bodyText(for message: MessageDisplay) -> String {
        switch message.messageType {
        case .text, .system:
            return message.content
        case .voice:
            if let duration = message.voiceDuration, duration >= 0.5 {
                let totalSeconds = max(0, Int(duration.rounded()))
                let minutes = totalSeconds / 60
                let seconds = totalSeconds % 60
                return String(
                    format: "settings.export.messages.voice.duration".localized,
                    minutes,
                    seconds
                )
            }
            return "settings.export.messages.voice".localized
        case .image:
            return "settings.export.messages.photo".localized
        case .video:
            return "settings.export.messages.video".localized
        }
    }
    
    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private static let exportedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        if let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           !selectedLanguage.isEmpty {
            formatter.locale = Locale(identifier: selectedLanguage)
        }
        return formatter
    }()
    
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private static let dayHeaderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        if let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           !selectedLanguage.isEmpty {
            formatter.locale = Locale(identifier: selectedLanguage)
        }
        return formatter
    }()
    
    private static let messageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
