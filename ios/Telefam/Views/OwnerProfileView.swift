import SwiftUI
import PhotosUI
import UIKit

private struct OwnerScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OwnerProfileView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality
    let isRegularWidth: Bool
    let bottomNavInsetPadding: CGFloat
    let onBottomBarVisibilityChange: (Bool) -> Void

    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var backgroundPickerItems: [PhotosPickerItem] = []
    @State private var showBackgroundPhotoPicker: Bool = false
    @State private var pendingCropImage: IdentifiableOwnerUIImage? = nil
    @State private var showBackgroundManager: Bool = false
    @State private var comingSoonTitle: String? = nil
    @State private var activeBgIndex: Int = 0
    @State private var scrollOffsetY: CGFloat = 0
    @State private var lastScrollOffsetY: CGFloat = 0
    @State private var showStickyHeader: Bool = false
    @State private var shareSheetItems: SharePayloadIdentifiable? = nil

    private let slideTimer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()
    private var isDark: Bool { viewModel.isDarkTheme }
    private var brandRed: Color { TelefamColors.crimson }

    private var profile: MyProfilePayload? { viewModel.myProfile }
    private var displayName: String {
        if let n = profile?.full_name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
        if let n = viewModel.session?.display_name, !n.isEmpty { return n }
        return "Telefam User"
    }
    private var username: String { profile?.username ?? "" }
    private var bio: String { profile?.bio ?? "" }
    private var followersCount: Int64 { profile?.safeFollowersCount ?? 0 }
    private var followingCount: Int64 { profile?.safeFollowingCount ?? 0 }
    private var postsCount: Int64 { profile?.safePostsCount ?? 0 }
    private var viewsCount: Int64 { profile?.safeViewsCount ?? 0 }

    private var slideSources: [OwnerSlideSource] {
        if !viewModel.ownerLocalBackgroundPaths.isEmpty {
            return viewModel.ownerLocalBackgroundPaths.prefix(5).map { .localPath($0) }
        }
        return (profile?.safeBackgroundPhotos ?? []).prefix(5).map { .remote($0.url.isEmpty ? "/v1/profile/backgrounds/\($0.id)" : $0.url) }
    }

    private var collapseProgress: CGFloat {
        let scrolled = max(0, -scrollOffsetY)
        return min(1.0, scrolled / 180.0)
    }

    var body: some View {
        GeometryReader { outerGeo in
            let safeTop = outerGeo.safeAreaInsets.top
            let coverHeight: CGFloat = max(145, (isRegularWidth ? 270 : 230) - (collapseProgress * 60))

            ZStack(alignment: .top) {
                TelefamColors.background(isDark: isDark)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Track scroll offset smoothly
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: OwnerScrollOffsetKey.self, value: geo.frame(in: .named("ownerProfileScroll")).minY)
                        }
                        .frame(height: 0)

                        // Cover banner + top crimson wave + overlapping avatar + Edit/Settings buttons
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                // Cover Banner
                                ZStack(alignment: .bottomTrailing) {
                                    coverSlideshowView(height: coverHeight + safeTop, safeTop: safeTop)
                                        .offset(y: -collapseProgress * 22)

                                    // Layered Crimson Wave across very top
                                    OwnerTopCrimsonWaveView()
                                        .frame(height: 52 + safeTop)
                                        .frame(maxWidth: .infinity)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .allowsHitTesting(false)

                                    // Top-right 3-dash menu button ("Coming Soon")
                                    Button {
                                        comingSoonTitle = "Menu"
                                    } label: {
                                        MenuDashesVectorIcon()
                                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                                            .frame(width: 22, height: 22)
                                            .frame(width: 48, height: 48)
                                    }
                                    .padding(.top, max(6, safeTop))
                                    .padding(.trailing, 10)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                                    // Curved bottom arch cutout separating cover from profile info
                                    OwnerCoverBottomArch()
                                        .fill(TelefamColors.background(isDark: isDark))
                                        .frame(height: 36)
                                        .frame(maxWidth: .infinity)
                                        .allowsHitTesting(false)

                                    // Change Background Pill (bottom-right)
                                    Button {
                                        if slideSources.isEmpty {
                                            showBackgroundPhotoPicker = true
                                        } else {
                                            showBackgroundManager = true
                                        }
                                    } label: {
                                        HStack(spacing: 7) {
                                            if viewModel.isUploadingOwnerBackgrounds {
                                                ProgressView()
                                                    .tint(.white)
                                                    .scaleEffect(0.75)
                                            } else {
                                                CameraVectorIcon()
                                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                                    .frame(width: 17, height: 17)
                                            }
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text("Change")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white)
                                                Text("Background")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Color.black.opacity(0.62))
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                    }
                                    .padding(.trailing, 14)
                                    .padding(.bottom, 22)
                                }
                                .frame(height: coverHeight + safeTop)
                                .clipped()

                                // Action pills row aligned right of avatar: Edit Profile | Settings
                                HStack(spacing: 8) {
                                    Spacer(minLength: 122)

                                    Button {
                                        viewModel.openEditProfile()
                                    } label: {
                                        HStack(spacing: 5) {
                                            EditPencilVectorIcon()
                                                .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                                .frame(width: 15, height: 15)
                                            Text("Edit Profile")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(TelefamColors.surface(isDark: isDark))
                                        .overlay(
                                            Capsule().stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                    }
                                    .frame(minHeight: 48)

                                    Button {
                                        comingSoonTitle = "Settings"
                                    } label: {
                                        HStack(spacing: 5) {
                                            SettingsGearVectorIcon()
                                                .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                                .frame(width: 15, height: 15)
                                            Text("Settings")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: 36)
                                        .background(TelefamColors.surface(isDark: isDark))
                                        .overlay(
                                            Capsule().stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                    }
                                    .frame(minHeight: 48)
                                }
                                .padding(.trailing, 14)
                                .padding(.top, 2)
                            }

                            // Overlapping Circular Avatar + Camera Badge
                            let avatarScale = max(0.76, 1.0 - collapseProgress * 0.24)
                            ZStack(alignment: .bottomTrailing) {
                                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(TelefamColors.surface(isDark: isDark))
                                            .frame(width: 108, height: 108)
                                            .overlay(
                                                Circle().stroke(TelefamColors.background(isDark: isDark), lineWidth: 4)
                                            )
                                            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)

                                        OwnerAvatarImageView(
                                            localPath: viewModel.ownerLocalAvatarPath,
                                            avatarData: viewModel.avatarJPEGData,
                                            remotePath: profile?.avatar_url,
                                            fallbackInitials: String(displayName.prefix(2)).uppercased(),
                                            api: viewModel.api,
                                            token: viewModel.session?.access_token
                                        )
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                    }
                                }

                                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                                    Circle()
                                        .fill(TelefamColors.surface(isDark: isDark))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle().stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                                        .overlay(
                                            CameraVectorIcon()
                                                .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                                .frame(width: 16, height: 16)
                                        )
                                }
                                .offset(x: 2, y: 2)
                            }
                            .scaleEffect(avatarScale)
                            .padding(.leading, 18)
                            .padding(.top, coverHeight + safeTop - 74)
                        }

                        // Name (NO verification badge), Clickable @username copy, Quote Bio
                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayName)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                .lineLimit(2)

                            if !username.isEmpty {
                                Button {
                                    UIPasteboard.general.string = "@\(username)"
                                    viewModel.showOwnerProfileToast("Username copied")
                                } label: {
                                    Text("@\(username)")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                        .padding(.vertical, 3)
                                }
                            }

                            if !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("“")
                                        .font(.system(size: 32, weight: .black, design: .serif))
                                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                        .offset(y: -6)
                                    Text(bio)
                                        .font(.system(size: 15))
                                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 10)
                            }

                            // Clickable Followers | Following + Posts & Views right below + Share Profile crimson pill
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 0) {
                                        Button {
                                            viewModel.openConnectionsSheet(mode: "followers", quality: networkQuality)
                                        } label: {
                                            VStack(spacing: 1) {
                                                Text(formatCompactCount(followersCount))
                                                    .font(.system(size: 19, weight: .bold))
                                                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                                Text("Followers")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                            }
                                            .padding(.trailing, 14)
                                            .frame(minHeight: 44)
                                        }

                                        Rectangle()
                                            .fill(TelefamColors.border(isDark: isDark))
                                            .frame(width: 1, height: 30)

                                        Button {
                                            viewModel.openConnectionsSheet(mode: "following", quality: networkQuality)
                                        } label: {
                                            VStack(spacing: 1) {
                                                Text(formatCompactCount(followingCount))
                                                    .font(.system(size: 19, weight: .bold))
                                                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                                Text("Following")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                            }
                                            .padding(.leading, 14)
                                            .frame(minHeight: 44)
                                        }
                                    }

                                    // Posts & Views counts directly below Followers & Following
                                    HStack(spacing: 12) {
                                        Text("\(formatCompactCount(postsCount)) Posts")
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                        Text("•")
                                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                        Text("\(formatCompactCount(viewsCount)) Views")
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                    }
                                }

                                Spacer()

                                Button {
                                    let shareText = username.isEmpty
                                        ? displayName
                                        : "\(displayName) (@\(username)) • https://telefam.app/@\(username)"
                                    UIPasteboard.general.string = shareText
                                    viewModel.showOwnerProfileToast("Profile link copied")
                                    shareSheetItems = SharePayloadIdentifiable(items: [shareText])
                                } label: {
                                    HStack(spacing: 7) {
                                        ShareNodesVectorIcon()
                                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                            .frame(width: 17, height: 17)
                                        Text("Share Profile")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .background(brandRed)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 16)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)

                        // Category Pills Row (Posts, Reposts, Locked, Saved)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(OwnerProfileTabIOS.allCases) { tab in
                                    let selected = viewModel.ownerActiveCategory == tab
                                    Button {
                                        viewModel.selectOwnerProfileCategory(tab, quality: networkQuality)
                                    } label: {
                                        HStack(spacing: 6) {
                                            categoryIcon(tab: tab, selected: selected)
                                                .frame(width: 16, height: 16)
                                            Text(tab.title)
                                                .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                                                .foregroundColor(selected ? .white : TelefamColors.inkPrimary(isDark: isDark))
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(height: 38)
                                        .background(selected ? brandRed : TelefamColors.surface(isDark: isDark))
                                        .overlay(
                                            Capsule().stroke(selected ? Color.clear : TelefamColors.border(isDark: isDark), lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)

                        // Media Grid (3 columns on phone, 4 on iPad)
                        let items = viewModel.ownerItemsByCategory[viewModel.ownerActiveCategory] ?? []
                        let colCount = isRegularWidth ? 4 : 3
                        let gridCols = Array(repeating: GridItem(.flexible(), spacing: 4), count: colCount)

                        if viewModel.isLoadingOwnerItems && items.isEmpty {
                            ProgressView()
                                .tint(brandRed)
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                        } else if items.isEmpty {
                            VStack(spacing: 8) {
                                categoryIcon(tab: viewModel.ownerActiveCategory, selected: false)
                                    .frame(width: 28, height: 28)
                                Text(emptyLabelForTab(viewModel.ownerActiveCategory))
                                    .font(.system(size: 14))
                                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                        } else {
                            LazyVGrid(columns: gridCols, spacing: 4) {
                                ForEach(items) { item in
                                    Button {
                                        viewModel.openOwnerItem(item, quality: networkQuality)
                                    } label: {
                                        OwnerProfileGridTileView(
                                            item: item,
                                            api: viewModel.api,
                                            token: viewModel.session?.access_token
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(maxWidth: 920)
                            .frame(maxWidth: .infinity)
                        }

                        Spacer().frame(height: bottomNavInsetPadding + 28)
                    }
                }
                .coordinateSpace(name: "ownerProfileScroll")
                .onPreferenceChange(OwnerScrollOffsetKey.self) { val in
                    let delta = val - lastScrollOffsetY
                    if delta < -8 {
                        onBottomBarVisibilityChange(false)
                    } else if delta > 8 || val >= -4 {
                        onBottomBarVisibilityChange(true)
                    }
                    lastScrollOffsetY = val
                    scrollOffsetY = val
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showStickyHeader = val < -160
                    }
                }
                .refreshable {
                    await viewModel.refreshOwnerProfile(quality: networkQuality, isPullGesture: true)
                }

                // Compact Sticky Top Bar when scrolled down
                if showStickyHeader {
                    HStack {
                        Text(username.isEmpty ? displayName : "@\(username)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            comingSoonTitle = "Menu"
                        } label: {
                            MenuDashesVectorIcon()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                .frame(width: 20, height: 20)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, safeTop + 4)
                    .padding(.bottom, 8)
                    .background(brandRed.opacity(0.96))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            if slideSources.count > 1 && activeBgIndex >= slideSources.count {
                activeBgIndex = 0
            }
            Task {
                await viewModel.refreshOwnerProfile(quality: networkQuality, isPullGesture: false)
            }
        }
        .onReceive(slideTimer) { _ in
            guard slideSources.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.75)) {
                activeBgIndex = (activeBgIndex + 1) % slideSources.count
            }
        }
        .photosPicker(
            isPresented: $showBackgroundPhotoPicker,
            selection: $backgroundPickerItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: avatarPickerItem) { item in
            guard let item else { return }
            avatarPickerItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    pendingCropImage = IdentifiableOwnerUIImage(image: img)
                }
            }
        }
        .onChange(of: backgroundPickerItems) { items in
            guard !items.isEmpty else { return }
            let picked = items
            backgroundPickerItems = []
            Task {
                var payloads: [Data] = []
                for p in picked {
                    if let d = try? await p.loadTransferable(type: Data.self) {
                        payloads.append(d)
                    }
                }
                await viewModel.uploadOwnerBackgroundPhotos(rawImagesData: payloads, quality: networkQuality)
            }
        }
        .sheet(item: $pendingCropImage) { wrapped in
            PhotoCropSheet(source: wrapped.image, brandRed: brandRed) { jpeg in
                pendingCropImage = nil
                Task { await viewModel.setCroppedAvatar(jpegData: jpeg, quality: networkQuality) }
            } onCancel: {
                pendingCropImage = nil
            }
        }
        .sheet(isPresented: $showBackgroundManager) {
            backgroundManagerSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.ownerConnectionsMode != nil },
            set: { if !$0 { viewModel.ownerConnectionsMode = nil } }
        )) {
            connectionsSheet
        }
        .sheet(item: $viewModel.activeOwnerViewerItem) { item in
            ownerItemViewerSheet(item)
        }
        .sheet(item: $shareSheetItems) { payload in
            ActivityShareSheetIOS(items: payload.items)
        }
        .alert(comingSoonTitle ?? "Notice", isPresented: Binding(
            get: { comingSoonTitle != nil },
            set: { if !$0 { comingSoonTitle = nil } }
        )) {
            Button("OK", role: .cancel) { comingSoonTitle = nil }
        } message: {
            Text("Coming Soon")
        }
    }

    @ViewBuilder
    private func coverSlideshowView(height: CGFloat, safeTop: CGFloat) -> some View {
        let sources = slideSources
        ZStack {
            if sources.isEmpty {
                LinearGradient(
                    colors: [
                        Color(red: 128.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0),
                        Color(red: 224.0 / 255.0, green: 112.0 / 255.0, blue: 28.0 / 255.0),
                        Color(red: 31.0 / 255.0, green: 42.0 / 255.0, blue: 68.0 / 255.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                let idx = min(activeBgIndex, sources.count - 1)
                ForEach(Array(sources.enumerated()), id: \.offset) { offset, src in
                    OwnerSlideImageView(
                        source: src,
                        api: viewModel.api,
                        token: viewModel.session?.access_token
                    )
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .opacity(offset == idx ? 1.0 : 0.0)
                }
                .animation(.easeInOut(duration: 0.75), value: idx)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func categoryIcon(tab: OwnerProfileTabIOS, selected: Bool) -> some View {
        let color = selected ? Color.white : TelefamColors.inkPrimary(isDark: isDark)
        switch tab {
        case .posts:
            GridFourSquaresVectorIcon()
                .fill(color)
        case .reposts:
            RepostVectorIcon()
                .stroke(color, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        case .locked:
            LockVectorIcon()
                .stroke(color, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        case .saved:
            BookmarkVectorIcon()
                .stroke(color, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        }
    }

    private func emptyLabelForTab(_ tab: OwnerProfileTabIOS) -> String {
        switch tab {
        case .posts: return "No posts yet"
        case .reposts: return "No reposts yet"
        case .locked: return "No locked posts"
        case .saved: return "No saved posts yet"
        }
    }

    private var backgroundManagerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let remoteBgs = profile?.safeBackgroundPhotos ?? []
                    let localBgs = viewModel.ownerLocalBackgroundPaths
                    Text("Upload up to 5 background photos (\(remoteBgs.count)/5)")
                        .font(.system(size: 13))
                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))

                    ForEach(Array(remoteBgs.enumerated()), id: \.element.id) { idx, bg in
                        ZStack(alignment: .topTrailing) {
                            let lp = idx < localBgs.count ? localBgs[idx] : nil
                            OwnerSlideImageView(
                                source: lp.map { .localPath($0) } ?? .remote(bg.url.isEmpty ? "/v1/profile/backgrounds/\(bg.id)" : bg.url),
                                api: viewModel.api,
                                token: viewModel.session?.access_token
                            )
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(14)

                            Button {
                                Task { await viewModel.deleteOwnerBackgroundPhoto(backgroundId: bg.id, quality: networkQuality) }
                            } label: {
                                TrashVectorIcon()
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                    .frame(width: 17, height: 17)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.66))
                                    .clipShape(Circle())
                            }
                            .padding(8)
                        }
                    }

                    if remoteBgs.count < 5 {
                        Button {
                            showBackgroundManager = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showBackgroundPhotoPicker = true
                            }
                        } label: {
                            Text("Add Photos (\(5 - remoteBgs.count) left)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(brandRed)
                                .cornerRadius(12)
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(18)
            }
            .navigationTitle("Background Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showBackgroundManager = false }
                }
            }
        }
    }

    private var connectionsSheet: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingOwnerConnections && viewModel.ownerConnectionsUsers.isEmpty {
                    ProgressView().tint(brandRed)
                } else if viewModel.ownerConnectionsUsers.isEmpty {
                    Text(viewModel.ownerConnectionsMode == "followers" ? "No followers yet" : "Not following anyone yet")
                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                } else {
                    List(viewModel.ownerConnectionsUsers) { user in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(brandRed.opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String((user.full_name.isEmpty ? user.username : user.full_name).prefix(2)).uppercased())
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(brandRed)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.full_name.isEmpty ? user.username : user.full_name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                Text("@\(user.username)")
                                    .font(.system(size: 13))
                                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                            }
                            Spacer()
                            Button {
                                Task { await viewModel.toggleConnectionFollow(user, quality: networkQuality) }
                            } label: {
                                let filled = !user.is_following
                                Text(connectionButtonLabel(user.relationship))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(filled ? .white : brandRed)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .background(filled ? brandRed : Color.clear)
                                    .overlay(
                                        Capsule().stroke(filled ? Color.clear : brandRed.opacity(0.6), lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(viewModel.ownerConnectionsMode == "followers" ? "Followers" : "Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.ownerConnectionsMode = nil }
                }
            }
        }
    }

    private func ownerItemViewerSheet(_ item: OwnerProfileItem) -> some View {
        NavigationStack {
            VStack(spacing: 14) {
                if item.post_type == "text" {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(ownerColorFromHex(item.bg_color_hex, fallback: brandRed))
                        Text(item.body)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(24)
                    }
                    .frame(height: 300)
                } else {
                    let target = item.media_urls.first ?? item.thumbnail_url
                    OwnerSlideImageView(
                        source: .remote(target),
                        api: viewModel.api,
                        token: viewModel.session?.access_token
                    )
                    .frame(maxHeight: 360)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(16)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.system(size: 14))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.toggleOwnerPostLike(item)
                    } label: {
                        HStack(spacing: 6) {
                            HeartVectorIcon()
                                .fill(item.is_liked ? brandRed : Color.gray)
                                .frame(width: 17, height: 17)
                            Text(formatCompactCount(item.likes_count))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TelefamColors.border(isDark: isDark), lineWidth: 1))
                    }

                    Button {
                        viewModel.toggleOwnerPostSave(item, quality: networkQuality)
                    } label: {
                        HStack(spacing: 6) {
                            BookmarkVectorIcon()
                                .stroke(item.is_saved ? brandRed : TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                .frame(width: 17, height: 17)
                            Text(item.is_saved ? "Saved" : "Save")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TelefamColors.border(isDark: isDark), lineWidth: 1))
                    }

                    Button {
                        viewModel.toggleOwnerPostLock(item, quality: networkQuality)
                    } label: {
                        HStack(spacing: 6) {
                            LockVectorIcon()
                                .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                .frame(width: 17, height: 17)
                            Text(item.visibility == "private" ? "Unlock" : "Lock")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TelefamColors.border(isDark: isDark), lineWidth: 1))
                    }
                }
                Spacer()
            }
            .padding(18)
            .navigationTitle(item.post_type.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.activeOwnerViewerItem = nil }
                }
            }
        }
    }

    private func connectionButtonLabel(_ relationship: String) -> String {
        switch relationship {
        case "friends": return "Friends"
        case "following": return "Following"
        case "follow_back": return "Follow back"
        default: return "Follow"
        }
    }
}

private enum OwnerSlideSource {
    case localPath(String)
    case remote(String)
}

private struct IdentifiableOwnerUIImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct SharePayloadIdentifiable: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityShareSheetIOS: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct OwnerTopCrimsonWaveView: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            var back = Path()
            back.move(to: .zero)
            back.addLine(to: CGPoint(x: w, y: 0))
            back.addLine(to: CGPoint(x: w, y: h * 0.62))
            back.addCurve(
                to: CGPoint(x: w * 0.45, y: h * 0.72),
                control1: CGPoint(x: w * 0.80, y: h * 0.96),
                control2: CGPoint(x: w * 0.62, y: h * 0.46)
            )
            back.addCurve(
                to: CGPoint(x: 0, y: h * 0.82),
                control1: CGPoint(x: w * 0.25, y: h * 0.96),
                control2: CGPoint(x: w * 0.12, y: h * 0.98)
            )
            back.closeSubpath()
            ctx.fill(back, with: .color(Color(red: 229.0 / 255.0, green: 29.0 / 255.0, blue: 32.0 / 255.0).opacity(0.88)))

            var front = Path()
            front.move(to: .zero)
            front.addLine(to: CGPoint(x: w, y: 0))
            front.addLine(to: CGPoint(x: w, y: h * 0.50))
            front.addCurve(
                to: CGPoint(x: w * 0.42, y: h * 0.56),
                control1: CGPoint(x: w * 0.78, y: h * 0.86),
                control2: CGPoint(x: w * 0.60, y: h * 0.34)
            )
            front.addCurve(
                to: CGPoint(x: 0, y: h * 0.68),
                control1: CGPoint(x: w * 0.22, y: h * 0.82),
                control2: CGPoint(x: w * 0.08, y: h * 0.82)
            )
            front.closeSubpath()
            ctx.fill(front, with: .color(TelefamColors.crimson))
        }
    }
}

private struct OwnerCoverBottomArch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height * 0.06))
        p.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.92),
            control: CGPoint(x: rect.width * 0.44, y: rect.height * 0.96)
        )
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.closeSubpath()
        return p
    }
}

private struct OwnerAvatarImageView: View {
    let localPath: String?
    let avatarData: Data?
    let remotePath: String?
    let fallbackInitials: String
    let api: TelefamAPIClient
    let token: String?

    @State private var remoteImage: UIImage? = nil

    var body: some View {
        ZStack {
            TelefamColors.crimsonSoft
            if let d = avatarData, let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if let lp = localPath, let ui = UIImage(contentsOfFile: lp) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if let ri = remoteImage {
                Image(uiImage: ri).resizable().scaledToFill()
            } else {
                Text(fallbackInitials.isEmpty ? "T" : fallbackInitials)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(TelefamColors.crimson)
            }
        }
        .task(id: remotePath ?? "") {
            guard avatarData == nil, localPath == nil,
                  let rp = remotePath, !rp.isEmpty, let tok = token else { return }
            if let data = try? await api.downloadBinary(token: tok, pathOrURL: rp),
               let img = UIImage(data: data) {
                remoteImage = img
            }
        }
    }
}

private struct OwnerSlideImageView: View {
    let source: OwnerSlideSource
    let api: TelefamAPIClient
    let token: String?

    @State private var loadedImage: UIImage? = nil

    var body: some View {
        ZStack {
            Color(red: 36.0 / 255.0, green: 42.0 / 255.0, blue: 54.0 / 255.0)
            switch source {
            case .localPath(let path):
                if let ui = UIImage(contentsOfFile: path) {
                    Image(uiImage: ui).resizable().scaledToFill()
                }
            case .remote:
                if let ui = loadedImage {
                    Image(uiImage: ui).resizable().scaledToFill()
                }
            }
        }
        .task(id: taskKey) {
            if case .remote(let path) = source, let tok = token, !path.isEmpty {
                if let data = try? await api.downloadBinary(token: tok, pathOrURL: path),
                   let ui = UIImage(data: data) {
                    loadedImage = ui
                }
            }
        }
    }

    private var taskKey: String {
        switch source {
        case .localPath(let p): return "l_\(p)"
        case .remote(let r): return "r_\(r)"
        }
    }
}

private struct OwnerProfileGridTileView: View {
    let item: OwnerProfileItem
    let api: TelefamAPIClient
    let token: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if item.post_type == "text" {
                    ZStack {
                        ownerColorFromHex(item.bg_color_hex, fallback: TelefamColors.crimson)
                        Text(item.body)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(8)
                    }
                } else {
                    let thumb = !item.thumbnail_url.isEmpty ? item.thumbnail_url : (item.media_urls.first ?? "")
                    OwnerSlideImageView(
                        source: .remote(thumb),
                        api: api,
                        token: token
                    )
                }

                // Bottom scrim
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Top-right media badge
                if item.post_type == "video" {
                    PlayTriangleVectorIcon()
                        .fill(Color.white)
                        .frame(width: 15, height: 15)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(7)
                } else if item.post_type == "photos" {
                    PhotoFrameVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(7)
                }

                // Bottom-left white heart + formatted likes count
                HStack(spacing: 4) {
                    HeartVectorIcon()
                        .fill(Color.white)
                        .frame(width: 13, height: 13)
                    Text(formatCompactCount(item.likes_count))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .cornerRadius(8)
        }
        .aspectRatio(0.86, contentMode: .fit)
    }
}

private func formatCompactCount(_ raw: Int64) -> String {
    if raw >= 1_000_000 {
        return String(format: "%.1fM", Double(raw) / 1_000_000.0).replacingOccurrences(of: ".0M", with: "M")
    }
    if raw >= 1_000 {
        return String(format: "%.1fK", Double(raw) / 1_000.0).replacingOccurrences(of: ".0K", with: "K")
    }
    return String(raw)
}

private func ownerColorFromHex(_ raw: String, fallback: Color) -> Color {
    var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("#") { clean.removeFirst() }
    guard clean.count == 6, let val = UInt64(clean, radix: 16) else { return fallback }
    return Color(
        red: Double((val >> 16) & 0xFF) / 255.0,
        green: Double((val >> 8) & 0xFF) / 255.0,
        blue: Double(val & 0xFF) / 255.0
    )
}
