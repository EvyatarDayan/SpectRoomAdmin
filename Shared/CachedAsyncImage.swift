import SwiftUI
import UIKit

final class ImageCacheService {
    static let shared = ImageCacheService()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 200
    }

    func image(for url: String) -> UIImage? {
        cache.object(forKey: url as NSString)
    }

    func insert(_ image: UIImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }
    
    func prefetch(_ url: URL) {
        let key = url.absoluteString
        guard image(for: key) == nil else { return }
        Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return
                }
                guard let uiImage = UIImage(data: data) else { return }
                await MainActor.run {
                    ImageCacheService.shared.insert(uiImage, for: key)
                }
            } catch {
                // Best-effort warmup.
            }
        }
    }
}

@MainActor
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var didFail = false
    private let url: URL?
    private var isLoading = false
    private let maxAttempts = 3

    init(url: URL?) {
        self.url = url
    }

    func load(force: Bool = false) {
        guard let url else { return }
        if !force {
            guard !isLoading else { return }
            guard image == nil else { return }
        }

        if !force, let cached = ImageCacheService.shared.image(for: url.absoluteString) {
            image = cached
            didFail = false
            return
        }

        isLoading = true
        didFail = false

        Task {
            var lastError: Error?
            for attempt in 1...maxAttempts {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    guard let uiImage = UIImage(data: data) else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    ImageCacheService.shared.insert(uiImage, for: url.absoluteString)
                    await MainActor.run {
                        self.image = uiImage
                        self.didFail = false
                        self.isLoading = false
                    }
                    return
                } catch {
                    lastError = error
                    if attempt < maxAttempts {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 350_000_000)
                    }
                }
            }

            print("❌ CachedImageLoader failed for \(url.absoluteString): \(lastError?.localizedDescription ?? "unknown")")
            await MainActor.run {
                self.didFail = self.image == nil
                self.isLoading = false
            }
        }
    }

    func retry() {
        image = nil
        load(force: true)
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    @StateObject private var loader: CachedImageLoader
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        _loader = StateObject(wrappedValue: CachedImageLoader(url: url))
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loader.load()
        }
    }
}

/// Chat image loader with cache, retries, and tap-to-retry on failure.
struct ChatCachedImage: View {
    let url: URL?
    var maxWidth: CGFloat = 150
    var maxHeight: CGFloat = 150
    
    @StateObject private var loader: CachedImageLoader
    
    init(url: URL?, maxWidth: CGFloat = 150, maxHeight: CGFloat = 150) {
        self.url = url
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        _loader = StateObject(wrappedValue: CachedImageLoader(url: url))
    }
    
    var body: some View {
        ZStack {
            if let uiImage = loader.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .cornerRadius(10)
            } else if loader.didFail {
                Button {
                    loader.retry()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(SpectRoomTheme.secondaryText)
                        Text("messages.image.retry".localized)
                            .font(.caption)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                    .frame(width: maxWidth, height: maxHeight)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                ProgressView()
                    .frame(width: maxWidth, height: maxHeight)
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        .onAppear {
            loader.load()
        }
    }
}
