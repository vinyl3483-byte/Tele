import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var viewModel: TelefamViewModel
    @ObservedObject var network: NetworkMonitor
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var messageDraft = ""
    @State private var showNewChatSheet = false
    @State private var newChatTitle = ""
    @State private var showNotificationsSheet = false
    @State private var isBottomBarVisible = true

    private var isDark: Bool { viewModel.isDarkTheme }
    private let brandRed = TelefamColors.crimson

    private var pillBg: Color {
        isDark ? TelefamColors.darkHomePill : TelefamColors.crimsonDark
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if viewModel.activeTab == .contacts {
                    ContactsTopBarView(viewModel: viewModel, networkQuality: network.quality)
                } else {
                    topBar
                }

                ZStack {
                    TelefamColors.background(isDark: isDark)
                    if sizeClass == .regular {
                        HStack(spacing: 0) {
                            sideRail
                            Rectangle()
                                .fill(TelefamColors.border(isDark: isDark))
                                .frame(width: 1)
                            if viewModel.activeTab == .contacts {
                                ContactsContentView(
                                    viewModel: viewModel,
                                    networkQuality: network.quality,
                                    isRegularWidth: true,
                                    onBottomBarVisibilityChange: { _ in }
                                )
                            } else {
                                mainContent
                            }
                        }
                    } else {
                        if viewModel.activeTab == .contacts {
                            ContactsContentView(
                                viewModel: viewModel,
                                networkQuality: network.quality,
                                isRegularWidth: false,
                                onBottomBarVisibilityChange: { visible in
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isBottomBarVisible = visible
                                    }
                                }
                            )
                            .telefamSwipeBack {
                                viewModel.activeTab = .chats
                                isBottomBarVisible = true
                            }
                        } else {
                            mainContent
                        }
                    }
                }
                .clipShape(TopRoundedShape(radius: viewModel.activeTab == .contacts ? 0 : 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(brandRed.ignoresSafeArea(edges: .top))

            if sizeClass != .regular,
               (viewModel.activeTab != .chats || viewModel.selectedConversationId == nil),
               isBottomBarVisible {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let activeToast = viewModel.contactsToastMessage {
                Text(activeToast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.88))
                    .cornerRadius(20)
                    .padding(.bottom, 84)
            }
        }
        .sheet(isPresented: $showNewChatSheet) {
            NavigationStack {
                Form {
                    TextField("Recipient name or email", text: $newChatTitle)
                }
                .navigationTitle("Start chat")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNewChatSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            let title = newChatTitle
                            newChatTitle = ""
                            showNewChatSheet = false
                            Task { await viewModel.createConversationOfflineFirst(title: title) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNotificationsSheet) {
            notificationsSheetView
        }
        .fullScreenCover(isPresented: $viewModel.isPostComposerOpen) {
            PostCreatorView(viewModel: viewModel, networkQuality: network.quality)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                SearchVectorIcon()
                    .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 18, height: 18)
                TextField(
                    "",
                    text: $viewModel.homeSearchQuery,
                    prompt: Text("Search chats, people, groups")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.72))
                )
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                if !viewModel.homeSearchQuery.isEmpty {
                    Button {
                        viewModel.homeSearchQuery = ""
                    } label: {
                        PlusVectorIcon()
                            .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(45))
                            .frame(width: 15, height: 15)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: TelefamMetrics.searchBarHeight)
            .background(pillBg)
            .overlay(
                RoundedRectangle(cornerRadius: TelefamMetrics.searchBarRadius)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(TelefamMetrics.searchBarRadius)

            Button {
                viewModel.toggleTheme()
            } label: {
                HStack(spacing: 6) {
                    if isDark {
                        MoonVectorIcon()
                            .stroke(brandRed, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 15, height: 15)
                    } else {
                        SunVectorIcon()
                            .stroke(Color(red: 251.0 / 255.0, green: 191.0 / 255.0, blue: 36.0 / 255.0), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 15, height: 15)
                    }
                    Text(isDark ? "Dark" : "Light")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 13)
                .frame(height: TelefamMetrics.themePillHeight)
                .background(pillBg)
                .overlay(
                    RoundedRectangle(cornerRadius: TelefamMetrics.themePillRadius)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .cornerRadius(TelefamMetrics.themePillRadius)
            }
            .frame(minHeight: TelefamMetrics.minTouchSize)

            Button {
                showNotificationsSheet = true
                Task { await viewModel.refreshNotifications(quality: network.quality) }
            } label: {
                ZStack(alignment: .topTrailing) {
                    BellVectorIcon()
                        .fill(Color.white)
                        .frame(width: TelefamMetrics.topIconSize, height: TelefamMetrics.topIconSize)
                    if viewModel.unreadNotificationCount > 0 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
                .frame(width: TelefamMetrics.topIconTouch, height: TelefamMetrics.topIconTouch)
            }

            Menu {
                Button("Sync") {
                    Task { await viewModel.syncAll(quality: network.quality) }
                }
                Button("Edit profile") {
                    viewModel.openEditProfile()
                }
                Divider()
                Button("Sign out", role: .destructive) {
                    viewModel.signOut()
                }
            } label: {
                MoreVertVectorIcon()
                    .fill(Color.white)
                    .frame(width: TelefamMetrics.topIconSize, height: TelefamMetrics.topIconSize)
                    .frame(width: TelefamMetrics.topIconTouch, height: TelefamMetrics.topIconTouch)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.activeTab {
        case .chats:
            chatsMainContent
        case .feeds:
            feedsContentView
        case .profile:
            profileOverviewView
        case .contacts:
            EmptyView()
        }
    }

    @ViewBuilder
    private var chatsMainContent: some View {
        if let convId = viewModel.selectedConversationId,
           let conv = viewModel.conversations.first(where: { $0.id == convId }) {
            chatThreadView(conv)
        } else if viewModel.filteredConversations.isEmpty {
            emptyStateView
        } else {
            List(viewModel.filteredConversations) { conv in
                Button {
                    viewModel.selectedConversationId = conv.id
                    Task { await viewModel.syncAll(quality: network.quality) }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(brandRed.opacity(0.14))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Text(String(conv.title.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundColor(brandRed)
                            )
                        Text(conv.title)
                            .font(.body.weight(.semibold))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(TelefamColors.surface(isDark: isDark))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showNewChatSheet = true
                } label: {
                    PlusVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .frame(width: 56, height: 56)
                        .background(brandRed)
                        .clipShape(Circle())
                        .shadow(radius: 6)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 82)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(brandRed.opacity(0.14))
                    .frame(width: 72, height: 72)
                ChatOutlineVectorIcon()
                    .stroke(brandRed, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 32, height: 32)
            }

            Text("Start a conversation")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))

            Text("Tap the button below to chat with your friends, family or groups")
                .font(.system(size: 14))
                .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                showNewChatSheet = true
            } label: {
                HStack(spacing: 8) {
                    ChatPlusVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                    Text("Start chat")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .frame(height: TelefamMetrics.startChatHeight)
                .background(brandRed)
                .cornerRadius(TelefamMetrics.startChatRadius)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedsContentView: some View {
        ZStack(alignment: .bottomTrailing) {
            if viewModel.isLoadingFeed && viewModel.feedPosts.isEmpty {
                ProgressView()
                    .tint(brandRed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredFeedPosts.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(brandRed.opacity(0.14))
                            .frame(width: 72, height: 72)
                        FeedsVectorIcon()
                            .stroke(brandRed, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 30, height: 30)
                    }
                    Text("No posts yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    Button {
                        viewModel.openPostComposer()
                    } label: {
                        Text("Create post")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 48)
                            .background(brandRed)
                            .cornerRadius(24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredFeedPosts) { post in
                            feedPostCard(post)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, sizeClass == .regular ? 24 : 96)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await viewModel.refreshFeedPosts(quality: network.quality)
                }
            }

            Button {
                viewModel.openPostComposer()
            } label: {
                PlusVectorIcon()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .frame(width: 56, height: 56)
                    .background(brandRed)
                    .clipShape(Circle())
                    .shadow(radius: 6)
            }
            .padding(.trailing, 18)
            .padding(.bottom, sizeClass == .regular ? 24 : 84)
        }
    }

    private func feedPostCard(_ post: FeedPostItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(brandRed.opacity(0.14))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String((post.author_name.isEmpty ? "T" : post.author_name).prefix(1)).uppercased())
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(brandRed)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author_name.isEmpty ? post.author_handle : post.author_name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    if !post.author_handle.isEmpty {
                        Text("@\(post.author_handle)")
                            .font(.system(size: 12))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    }
                }
                Spacer()
                Text(post.post_type.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(brandRed)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(brandRed.opacity(0.12))
                    .cornerRadius(12)
            }

            if !post.body.isEmpty {
                Text(post.body)
                    .font(.system(size: 15))
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if post.media_count > 0 {
                Text(post.post_type == "video" ? "Video post" : "\(post.media_count) photo(s)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
            }

            if !post.song_title.isEmpty {
                Text("\(post.song_title)\(post.song_artist.isEmpty ? "" : " - \(post.song_artist)")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(brandRed)
            }

            if let tags = post.hashtags, !tags.isEmpty {
                Text(tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(brandRed)
            }
        }
        .padding(14)
        .background(TelefamColors.surface(isDark: isDark))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private var profileOverviewView: some View {
        let profile = viewModel.myProfile
        let displayName = (profile?.full_name.isEmpty == false ? profile?.full_name : viewModel.session?.display_name) ?? "Telefam User"
        let handle = profile?.username ?? ""
        let email = profile?.email ?? viewModel.session?.email ?? ""

        return ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Circle()
                        .fill(brandRed.opacity(0.14))
                        .frame(width: 82, height: 82)
                        .overlay(
                            Text(String(displayName.prefix(2)).uppercased())
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(brandRed)
                        )
                        .overlay(Circle().stroke(brandRed, lineWidth: 2))

                    Text(displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))

                    if !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    }

                    if !email.isEmpty {
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    }

                    if let bio = profile?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 14))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                            .multilineTextAlignment(.center)
                    }

                    if let loc = profile?.location, !loc.isEmpty {
                        Text(loc)
                            .font(.system(size: 13))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(TelefamColors.surface(isDark: isDark))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                )
                .cornerRadius(18)

                Button {
                    viewModel.openEditProfile()
                } label: {
                    Text("Edit profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(brandRed)
                        .cornerRadius(12)
                }

                Button {
                    Task { await viewModel.syncAll(quality: network.quality) }
                } label: {
                    HStack(spacing: 8) {
                        SyncVectorIcon()
                            .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                        Text("Sync")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(TelefamColors.surface(isDark: isDark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }

                Button {
                    viewModel.signOut()
                } label: {
                    HStack(spacing: 8) {
                        SignOutVectorIcon()
                            .stroke(brandRed, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                        Text("Sign out")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(brandRed)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(TelefamColors.surface(isDark: isDark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(brandRed.opacity(0.45), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, sizeClass == .regular ? 28 : 96)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
    }

    private var notificationsSheetView: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingNotifications && viewModel.notifications.isEmpty {
                    ProgressView().tint(brandRed)
                } else if viewModel.notifications.isEmpty {
                    Text("No notifications")
                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                } else {
                    List(viewModel.notifications) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if !item.actor_name.isEmpty {
                                    Text(item.actor_name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                }
                                Spacer()
                                if !item.is_read {
                                    Circle()
                                        .fill(brandRed)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            Text(item.message)
                                .font(.system(size: 13))
                                .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showNotificationsSheet = false }
                }
                if viewModel.unreadNotificationCount > 0 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Mark all read") {
                            Task { await viewModel.markNotificationsRead(quality: network.quality) }
                        }
                    }
                }
            }
        }
    }

    private func chatThreadView(_ conv: ConversationItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    viewModel.selectedConversationId = nil
                } label: {
                    ArrowLeftVectorIcon()
                        .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                        .frame(width: TelefamMetrics.topIconTouch, height: TelefamMetrics.topIconTouch)
                }
                Text(conv.title)
                    .font(.headline)
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Rectangle()
                .fill(TelefamColors.border(isDark: isDark))
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { msg in
                        let isMine = msg.sender_id == viewModel.session?.user_id
                        HStack {
                            if isMine { Spacer() }
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(msg.body)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(isMine ? brandRed : TelefamColors.surface(isDark: isDark))
                                    .foregroundColor(isMine ? .white : TelefamColors.inkPrimary(isDark: isDark))
                                    .cornerRadius(16)
                                if isMine {
                                    Text(msg.isPendingSync ? "Queued" : "Sent")
                                        .font(.caption2)
                                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                }
                            }
                            if !isMine { Spacer() }
                        }
                    }
                }
                .padding()
            }

            Rectangle()
                .fill(TelefamColors.border(isDark: isDark))
                .frame(height: 1)

            HStack(spacing: 8) {
                TextField("Write a message", text: $messageDraft)
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(TelefamColors.surface(isDark: isDark))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                    )
                    .cornerRadius(24)

                Button {
                    let text = messageDraft
                    messageDraft = ""
                    Task { await viewModel.sendMessageOfflineFirst(conversationId: conv.id, body: text) }
                } label: {
                    PaperPlaneSendVectorIcon()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .frame(width: 48, height: 48)
                        .background(brandRed)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .telefamSwipeBack(enabled: sizeClass != .regular) {
            viewModel.selectedConversationId = nil
        }
    }

    private var bottomBar: some View {
        let chatsActive = viewModel.activeTab == .chats
        let contactsActive = viewModel.activeTab == .contacts
        let feedsActive = viewModel.activeTab == .feeds
        let profileActive = viewModel.activeTab == .profile
        let inactiveColor = TelefamColors.inkSecondary(isDark: isDark)

        return VStack(spacing: 0) {
            Rectangle()
                .fill(TelefamColors.border(isDark: isDark))
                .frame(height: 1)

            HStack(spacing: 0) {
                Button {
                    viewModel.activeTab = .chats
                    isBottomBarVisible = true
                } label: {
                    navItemLabel(title: "Chats", active: chatsActive, inactiveColor: inactiveColor) {
                        if chatsActive {
                            ChatFilledVectorIcon()
                                .fill(brandRed)
                        } else {
                            ChatOutlineVectorIcon()
                                .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54)

                Button {
                    viewModel.activeTab = .contacts
                    isBottomBarVisible = true
                    Task { await viewModel.refreshContacts(reset: true, quality: network.quality) }
                } label: {
                    navItemLabel(title: "Contacts", active: contactsActive, inactiveColor: inactiveColor) {
                        if contactsActive {
                            ContactsFilledVectorIcon()
                                .fill(brandRed)
                        } else {
                            ContactsOutlineVectorIcon()
                                .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54)

                Button {
                    viewModel.openPostComposer()
                } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(brandRed)
                            .frame(width: TelefamMetrics.bottomPostSize, height: TelefamMetrics.bottomPostSize)
                            .overlay(
                                PlusVectorIcon()
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                    .frame(width: 20, height: 20)
                            )
                            .offset(y: -4)
                        Text("Post")
                            .font(.system(size: 11))
                            .foregroundColor(inactiveColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }

                Button {
                    viewModel.activeTab = .feeds
                    isBottomBarVisible = true
                    Task { await viewModel.refreshFeedPosts(quality: network.quality) }
                } label: {
                    navItemLabel(title: "Feeds", active: feedsActive, inactiveColor: inactiveColor) {
                        FeedsVectorIcon()
                            .stroke(feedsActive ? brandRed : inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54)

                Button {
                    viewModel.activeTab = .profile
                    isBottomBarVisible = true
                    Task { await viewModel.refreshMyProfile(quality: network.quality) }
                } label: {
                    navItemLabel(title: "Profile", active: profileActive, inactiveColor: inactiveColor) {
                        ProfileVectorIcon()
                            .stroke(profileActive ? brandRed : inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .padding(.horizontal, 6)
            .frame(height: TelefamMetrics.bottomBarHeight)
        }
        .background(TelefamColors.bar(isDark: isDark))
    }

    private var sideRail: some View {
        let chatsActive = viewModel.activeTab == .chats
        let contactsActive = viewModel.activeTab == .contacts
        let feedsActive = viewModel.activeTab == .feeds
        let profileActive = viewModel.activeTab == .profile
        let inactiveColor = TelefamColors.inkSecondary(isDark: isDark)

        return VStack(spacing: 18) {
            Button {
                viewModel.activeTab = .chats
                viewModel.selectedConversationId = nil
            } label: {
                navItemLabel(title: "Chats", active: chatsActive, inactiveColor: inactiveColor) {
                    if chatsActive {
                        ChatFilledVectorIcon()
                            .fill(brandRed)
                    } else {
                        ChatOutlineVectorIcon()
                            .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)

            Button {
                viewModel.activeTab = .contacts
                Task { await viewModel.refreshContacts(reset: true, quality: network.quality) }
            } label: {
                navItemLabel(title: "Contacts", active: contactsActive, inactiveColor: inactiveColor) {
                    if contactsActive {
                        ContactsFilledVectorIcon()
                            .fill(brandRed)
                    } else {
                        ContactsOutlineVectorIcon()
                            .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)

            Button {
                viewModel.openPostComposer()
            } label: {
                Circle()
                    .fill(brandRed)
                    .frame(width: TelefamMetrics.railPostSize, height: TelefamMetrics.railPostSize)
                    .overlay(
                        PlusVectorIcon()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .frame(width: 20, height: 20)
                    )
            }

            Button {
                viewModel.activeTab = .feeds
                Task { await viewModel.refreshFeedPosts(quality: network.quality) }
            } label: {
                navItemLabel(title: "Feeds", active: feedsActive, inactiveColor: inactiveColor) {
                    FeedsVectorIcon()
                        .stroke(feedsActive ? brandRed : inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)

            Button {
                viewModel.activeTab = .profile
                Task { await viewModel.refreshMyProfile(quality: network.quality) }
            } label: {
                navItemLabel(title: "Profile", active: profileActive, inactiveColor: inactiveColor) {
                    ProfileVectorIcon()
                        .stroke(profileActive ? brandRed : inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)

            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: TelefamMetrics.railWidth)
        .background(TelefamColors.rail(isDark: isDark))
    }

    private func navItemLabel<Icon: View>(
        title: String,
        active: Bool,
        inactiveColor: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 3) {
            icon()
                .frame(width: 22, height: 22)
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundColor(active ? brandRed : inactiveColor)
        }
    }
}

private struct TopRoundedShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(p.cgPath)
    }
}
