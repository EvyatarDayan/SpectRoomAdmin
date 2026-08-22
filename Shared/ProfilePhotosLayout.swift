//
//  ProfilePhotosLayout.swift
//  SpectRoom
//
//  Clean photo presentation shared by My Profile, Edit Profile, and other-user profiles.
//  Visual language matches the home discover cards: full-bleed images, soft shadows, no blur panels.
//

import SwiftUI

enum ProfilePhotoStyle {
    static let cardCorner: CGFloat = 24
    static let photoCorner: CGFloat = 18
    static let mainPhotoHeight: CGFloat = 280
    static let galleryPhotoSize: CGFloat = 104
    static let cardShadow = Color.black.opacity(0.12)
}

/// Local gallery pick with a stable identity so deletes target the correct cell.
struct LocalGalleryImage: Identifiable, Equatable {
    let id: UUID
    let image: UIImage
    
    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.image = image
    }
    
    static func == (lhs: LocalGalleryImage, rhs: LocalGalleryImage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Large primary profile photo - full-bleed rounded card.
struct ProfileMainPhotoCard: View {
    let imageURL: String?
    let localImage: UIImage?
    var placeholderSystemName: String = "person.fill"
    var showsCameraBadge: Bool = false
    var onTap: (() -> Void)?
    
    init(
        imageURL: String? = nil,
        localImage: UIImage? = nil,
        placeholderSystemName: String = "person.fill",
        showsCameraBadge: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.imageURL = imageURL
        self.localImage = localImage
        self.placeholderSystemName = placeholderSystemName
        self.showsCameraBadge = showsCameraBadge
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottomTrailing) {
                // Clear frame first so scaledToFill images can't expand the parent
                // (that was collapsing horizontal padding on the whole profile scroll).
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: ProfilePhotoStyle.mainPhotoHeight)
                    .overlay { photoContent }
                    .clipped()
                
                if showsCameraBadge {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.blue)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                        .padding(14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ProfilePhotoStyle.cardCorner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ProfilePhotoStyle.cardCorner, style: .continuous))
            .shadow(color: ProfilePhotoStyle.cardShadow, radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
    
    @ViewBuilder
    private var photoContent: some View {
        if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
        } else if let imageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.18))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: placeholderSystemName)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(SpectRoomTheme.secondaryText)
                    if showsCameraBadge {
                        Text("profile.edit.add.photo".localized)
                            .font(.subheadline)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                }
            )
    }
}

/// Gallery strip / grid inside a clean card (no frosted blur background).
struct ProfileGalleryPhotosCard: View {
    let photoURLs: [String]
    var localImages: [LocalGalleryImage] = []
    /// Pass `nil` to hide the section title (e.g. other-user profiles).
    var title: String? = "profile.my.photos".localized
    var allowsPaging: Bool = true
    var emptyMessage: String = "profile.no.photos".localized
    var onSelectRemote: ((Int) -> Void)?
    var onDeleteRemote: ((String) -> Void)?
    var onDeleteLocal: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var maxRemoteVisible: Int = 5
    var showValidation: Bool? = nil
    /// White section card used on edit profile; leave off for read-only profiles.
    var usesWhiteBackground: Bool = false
    /// Optional caption under the grid (e.g. min/max photo hint).
    var footerText: String? = nil
    
    @State private var pageIndex = 0
    
    private var remoteToShow: [String] {
        Array(photoURLs.prefix(maxRemoteVisible))
    }
    
    private var localToShow: [LocalGalleryImage] {
        let remaining = max(0, maxRemoteVisible - remoteToShow.count)
        return Array(localImages.prefix(remaining))
    }
    
    private var totalCount: Int {
        photoURLs.count + localImages.count
    }
    
    private var canAddMore: Bool {
        totalCount < maxRemoteVisible
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || showValidation != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    if let showValidation {
                        Image(systemName: showValidation ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(showValidation ? .green : .secondary.opacity(0.35))
                    }
                }
            }
            
            if remoteToShow.isEmpty && localToShow.isEmpty && onAdd == nil {
                Text(emptyMessage)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if allowsPaging && remoteToShow.count > 3 && onAdd == nil && localToShow.isEmpty {
                pagedGallery
            } else {
                photoGrid
            }
            
            if let footerText {
                Text(footerText)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ProfilePhotoStyle.cardCorner, style: .continuous)
                .fill(usesWhiteBackground ? SpectRoomTheme.card : SpectRoomTheme.card)
        )
        .shadow(color: ProfilePhotoStyle.cardShadow, radius: 16, x: 0, y: 8)
    }
    
    private var photoGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ForEach(remoteToShow, id: \.self) { url in
                galleryThumb(
                    url: url,
                    remoteIndex: photoURLs.firstIndex(of: url) ?? 0
                )
            }
            
            ForEach(localToShow) { localPhoto in
                localThumb(localPhoto: localPhoto)
            }
            
            if let onAdd {
                Button(action: onAdd) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                        Text("profile.edit.add".localized)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: ProfilePhotoStyle.galleryPhotoSize)
                    .background(
                        RoundedRectangle(cornerRadius: ProfilePhotoStyle.photoCorner, style: .continuous)
                            .fill(SpectRoomTheme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ProfilePhotoStyle.photoCorner, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAddMore)
                .opacity(canAddMore ? 1.0 : 0.45)
            }
        }
    }
    
    private var pagedGallery: some View {
        let pageCount = max(1, (remoteToShow.count + 2) / 3)
        
        return VStack(spacing: 10) {
            TabView(selection: $pageIndex) {
                ForEach(0..<pageCount, id: \.self) { page in
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { slot in
                            let index = page * 3 + slot
                            if index < remoteToShow.count {
                                galleryThumb(url: remoteToShow[index], remoteIndex: index)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: ProfilePhotoStyle.galleryPhotoSize)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .tag(page)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: ProfilePhotoStyle.galleryPhotoSize + 4)
            
            if pageCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(pageIndex == index ? Color.primary.opacity(0.75) : Color.primary.opacity(0.18))
                            .frame(width: pageIndex == index ? 14 : 6, height: 6)
                    }
                }
            }
        }
    }
    
    private func galleryThumb(url: String, remoteIndex: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: ProfilePhotoStyle.galleryPhotoSize)
                .overlay {
                    CachedAsyncImage(url: URL(string: url)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                            )
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: ProfilePhotoStyle.photoCorner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ProfilePhotoStyle.photoCorner, style: .continuous))
                .onTapGesture {
                    onSelectRemote?(remoteIndex)
                }
            
            if let onDeleteRemote {
                Button(action: { onDeleteRemote(url) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity)
        .id(url) // Force CachedAsyncImage to rebuild when this URL identity moves/changes
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
    
    private func localThumb(localPhoto: LocalGalleryImage) -> some View {
        ZStack(alignment: .topTrailing) {
            // Clear frame first so scaledToFill can't expand LazyVGrid cells
            // (that was collapsing spacing on the second row).
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: ProfilePhotoStyle.galleryPhotoSize)
                .overlay {
                    Image(uiImage: localPhoto.image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: ProfilePhotoStyle.photoCorner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ProfilePhotoStyle.photoCorner, style: .continuous))
            
            if let onDeleteLocal {
                Button(action: { onDeleteLocal(localPhoto.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
}
