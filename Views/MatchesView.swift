//
//  MatchesView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

struct MatchesView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @State private var matches: [MatchDisplay] = []
    @State private var isLoading = true
    @State private var showingProfileModal = false
    @State private var selectedProfile: ProfileCard?
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    private let listPadding: CGFloat = 16
    private let rowSpacing: CGFloat = 14
    /// Same as search bar `.padding(.bottom, 10)`.
    private let searchContentSpacing: CGFloat = 10
    /// Height of the custom tab menu body (above the home indicator).
    private let tabMenuBodyHeight: CGFloat = 70

    private var cardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        return floor(screenWidth - (listPadding * 2))
    }
    
    private var visibleMatches: [MatchDisplay] {
        matches.filter { !appState.isHiddenByBlock($0.otherUser.userId) }
    }
    
    private var filteredMatches: [MatchDisplay] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleMatches }
        return visibleMatches.filter { matchMatchesSearch($0, query: query) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !isLoading && !visibleMatches.isEmpty {
                    matchesSearchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, searchContentSpacing)
                }
                
                Group {
                    if isLoading {
                        loadingView
                    } else if visibleMatches.isEmpty {
                        emptyMatchesView
                    } else {
                        ZStack {
                            matchesList
                            
                            if filteredMatches.isEmpty {
                                noSearchResultsView
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Mirror top spacing: 10pt gap, then reserve space for the overlay menu.
                Color.clear
                    .frame(height: tabMenuBodyHeight)
                    .padding(.top, searchContentSpacing)
            }
            .background(colorsBackground)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("matches.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
        }
        .navigationViewStyle(.stack)
        .onReceive(appState.$cachedMatches) { updatedMatches in
            matches = updatedMatches
            isLoading = false
        }
        .onAppear {
            loadMatches()
            refreshMatchEnergyLevels()
            appState.refreshBlockedByUsers()
        }
        .onChange(of: selectedTab) { tab in
            guard tab == 1 else { return }
            refreshMatchEnergyLevels()
        }
        .sheet(isPresented: Binding(
            get: {
                let isPresented = showingProfileModal
                print("🔍 MatchesView Sheet binding GET - isPresented: \(isPresented), selectedProfile: \(selectedProfile?.name ?? "nil")")
                return isPresented
            },
            set: { newValue in
                print("🔍 MatchesView Sheet binding SET - newValue: \(newValue), current showingProfileModal: \(showingProfileModal)")
                print("🔍 selectedProfile at set time: \(selectedProfile?.name ?? "nil"), userId: \(selectedProfile?.userId ?? "nil")")
                showingProfileModal = newValue
                print("🔍 showingProfileModal after set: \(showingProfileModal)")
            }
        )) {
            let _ = print("🔍 MatchesView Sheet closure EXECUTING - selectedProfile: \(selectedProfile?.name ?? "nil")")
            if let profile = selectedProfile {
                let _ = print("🔍 MatchesView Creating UserProfileModal with profile: \(profile.name), userId: \(profile.userId), age: \(profile.age)")
                UserProfileModal(profile: profile)
                    .environmentObject(appState)
            } else {
                let _ = print("❌ MatchesView selectedProfile is nil in sheet closure!")
                VStack {
                    Text("matches.error.no.profile".localized)
                        .foregroundColor(.red)
                    Button("common.close".localized) {
                        showingProfileModal = false
                    }
                }
            }
        }
    }

    private func loadMatches() {
        if matches.isEmpty {
            isLoading = true
        }
        Task {
            do {
                let cached = try await appState.getCachedOrFreshMatches()
                await MainActor.run {
                    self.matches = cached
                    self.isLoading = false
                }
                await appState.refreshCachedMatchEnergyLevels()
            } catch {
                print("❌ Error loading matches: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func refreshMatchEnergyLevels() {
        Task {
            await appState.refreshCachedMatchEnergyLevels()
        }
    }

    private func openProfile(for match: MatchDisplay) {
        guard !appState.isHiddenByBlock(match.otherUser.userId) else { return }
        print("🔍 Match card tapped for profile: \(match.otherUser.name)")
        selectedProfile = match.otherUser
        appState.viewedMatchProfileId = match.otherUser.userId
        showingProfileModal = true
    }

    private func openMessage(for match: MatchDisplay) {
        guard !appState.isHiddenByBlock(match.otherUser.userId) else { return }
        print("💬 Message button tapped for: \(match.otherUser.name)")
        let userId = match.otherUser.userId
        appState.viewedMatchProfileId = userId
        appState.conversationToOpenProfile = match.otherUser
        appState.conversationToOpenSenderId = userId
        selectedTab = 0
    }
    
    private func matchMatchesSearch(_ match: MatchDisplay, query: String) -> Bool {
        searchableProfileTexts(from: match.otherUser).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }
}

private extension MatchesView {
    var colorsBackground: some View {
        SpectRoomBackground()
    }

    var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("matches.loading".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var matchesList: some View {
        ScrollView {
            LazyVStack(spacing: rowSpacing) {
                ForEach(filteredMatches) { match in
                    MatchGridCard(
                        match: match,
                        cardWidth: cardWidth,
                        onTap: { openProfile(for: match) },
                        onMessage: { openMessage(for: match) }
                    )
                    .environmentObject(appState)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, listPadding)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
    
    var matchesSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(SpectRoomTheme.secondaryText)
            
            TextField("matches.search.placeholder".localized, text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(SpectRoomTheme.text)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($isSearchFieldFocused)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("matches.search.clear".localized)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpectRoomTheme.card)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        )
    }
    
    var noSearchResultsView: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(Color.blue.opacity(0.75))
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(SpectRoomTheme.card)
                    )
                    .offset(x: 6, y: 6)
            }
            .padding(.bottom, 4)
            
            Text("messages.search.no.results".localized)
                .font(.headline)
                .foregroundColor(.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Text("matches.search.no.results.hint".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func searchableProfileTexts(from profile: ProfileCard) -> [String] {
        var texts = [profile.name]
        
        if !profile.bio.isEmpty {
            texts.append(profile.bio)
        }
        
        if profile.shareLifestyle {
            texts.append(formattedLifestyle(profile.lifestyle))
        }
        
        if profile.shareBodyType, !profile.bodyType.isEmpty {
            texts.append(formattedBodyType(profile.bodyType))
        }
        
        if !profile.idealFirstDate.isEmpty {
            texts.append(formattedIdealFirstDate(profile.idealFirstDate))
        }
        
        for interest in profile.interests {
            texts.append(interest)
            texts.append(localizedInterest(interest))
        }
        
        return texts.filter { !$0.isEmpty }
    }
    
    func formattedLifestyle(_ lifestyle: String) -> String {
        switch lifestyle {
        case "independent":
            return "profile.edit.lifestyle.independent".localized
        case "familySupport":
            return "profile.edit.lifestyle.family".localized
        case "assistedSetting":
            return "profile.edit.lifestyle.assisted".localized
        default:
            return lifestyle.isEmpty ? "" : "profile.lifestyle.placeholder".localized
        }
    }
    
    func formattedBodyType(_ bodyType: String) -> String {
        switch bodyType {
        case "slim":
            return "profile.edit.body.type.slim".localized
        case "average":
            return "profile.edit.body.type.average".localized
        case "athletic":
            return "profile.edit.body.type.athletic".localized
        case "fullBodied":
            return "profile.edit.body.type.full.bodied".localized
        default:
            return bodyType
        }
    }
    
    func localizedInterest(_ interest: String) -> String {
        let key = "profile.edit.interest.\(interest.lowercased())"
        let localized = key.localized
        return localized == key ? interest : localized
    }
    
    func formattedIdealFirstDate(_ idealFirstDate: [String]) -> String {
        let formatted = idealFirstDate.map { option in
            switch option {
            case "relaxingParkWalk":
                return "profile.edit.ideal.date.relaxing.park.walk".localized
            case "cozyCafeMeet":
                return "profile.edit.ideal.date.cozy.cafe.meet".localized
            case "museumGalleryStroll":
                return "profile.edit.ideal.date.museum.gallery.stroll".localized
            case "cinemaMovieNight":
                return "profile.edit.ideal.date.cinema.movie.night".localized
            case "friendlyVideoChat":
                return "profile.edit.ideal.date.friendly.video.chat".localized
            default:
                return option
            }
        }
        return formatted.joined(separator: ", ")
    }

    var emptyMatchesView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("💕")
                    .font(.system(size: 48))
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(Color.pink.opacity(0.16))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.pink.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.pink.opacity(0.18), radius: 12, y: 4)
                
                Text("matches.empty".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
                
                Text("matches.empty.description".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    selectedTab = 2
                }) {
                    Text("messages.empty.no.matches.button".localized)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
                .padding(.horizontal, 30)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MatchGridCard: View {
    let match: MatchDisplay
    let cardWidth: CGFloat
    let onTap: () -> Void
    let onMessage: () -> Void
    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme

    private let cardPadding: CGFloat = 10
    private let contentSpacing: CGFloat = 12

    private var profile: ProfileCard { match.otherUser }

    private var photoSide: CGFloat {
        floor((cardWidth - (cardPadding * 2) - contentSpacing) / 2)
    }

    private var infoWidth: CGFloat {
        photoSide
    }

    private var displayDistance: String? {
        let distance = profile.distance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !distance.isEmpty, distance != "Matched" else { return nil }
        return distance
    }
    
    private var cardBackground: Color {
        SpectRoomTheme.card
    }
    
    private var nameColor: Color {
        SpectRoomTheme.text
    }
    
    private var distanceColor: Color {
        SpectRoomTheme.secondaryText
    }
    
    private var photoBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.white.opacity(0.9)
    }

    var body: some View {
        HStack(alignment: .center, spacing: contentSpacing) {
            ZStack(alignment: .bottom) {
                Button(action: onTap) {
                    profileImage
                        .frame(width: photoSide, height: photoSide)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(photoBorderColor, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)

                messageButton
                    .padding(.bottom, 10)
            }

            Button(action: onTap) {
                infoColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: infoWidth, height: photoSide)
        }
        .padding(cardPadding)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay {
            if isBlockedMatch {
                BlockedProfileLabel(dimmed: false, slanted: false)
                    .allowsHitTesting(false)
            }
        }
    }

    private var infoColumn: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            VStack(spacing: 0) {
                nameDistanceLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .frame(height: midY)

                Rectangle()
                    .fill(Color(white: colorScheme == .dark ? 0.55 : 0.72).opacity(0.4))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)

                energyLevelLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .frame(height: geo.size.height - midY - 1)
            }
        }
    }

    private var isBlockedMatch: Bool {
        appState.isMessagingBlocked(with: profile.userId)
    }

    private var nameDistanceLabel: some View {
        VStack(spacing: 4) {
            Text("\(firstName(from: profile.name)), \(profile.age)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(nameColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let displayDistance {
                Text(displayDistance)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(distanceColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
    }
    
    private var energyLevelLabel: some View {
        let option = EnergyLevelOption.resolved(from: profile.energyLevel)
        let title = String(format: "matches.energy.today".localized, option.title)
        // Hidden trailing emoji balances the leading one so only the text is
        // optically centered; visible emoji sits slightly left of the text.
        return HStack(alignment: .center, spacing: 6) {
            Text(option.emoji)
                .font(.system(size: 18))
                .offset(x: 12)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(option.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: max(0, infoWidth - 40))
            Text(option.emoji)
                .font(.system(size: 18))
                .hidden()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
    
    private var messageButton: some View {
        Button(action: onMessage) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("matches.message.button".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let profilePhotoURL = profile.imageURL, !profilePhotoURL.isEmpty {
            CachedAsyncImage(url: URL(string: profilePhotoURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                imagePlaceholder
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
            )
    }

    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
}

#Preview {
    MatchesView(selectedTab: .constant(1))
        .environmentObject(AppStateManager.shared)
}
