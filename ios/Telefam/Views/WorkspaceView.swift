import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var viewModel: TelefamViewModel
    @ObservedObject var network: NetworkMonitor
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var messageDraft = ""
    @State private var showNewChatSheet = false
    @State private var newChatTitle = ""
    @State private var toastText: String?
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
               (viewModel.activeTab == .contacts || viewModel.selectedConversationId == nil),
               isBottomBarVisible {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let activeToast = viewModel.contactsToastMessage ?? toastText {
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
        .fullScreenCover(isPresented: $viewModel.isPostComposerOpen) {
            PostCreatorView(viewModel: viewModel, networkQuality: network.quality)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                showComingSoon()
            } label: {
                HStack(spacing: 8) {
                    SearchVectorIcon()
                        .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 18, height: 18)
                    Text("Search chats, people, gr…")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: TelefamMetrics.searchBarHeight)
                .background(pillBg)
                .overlay(
                    RoundedRectangle(cornerRadius: TelefamMetrics.searchBarRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .cornerRadius(TelefamMetrics.searchBarRadius)
            }

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
                showComingSoon()
            } label: {
                BellVectorIcon()
                    .fill(Color.white)
                    .frame(width: TelefamMetrics.topIconSize, height: TelefamMetrics.topIconSize)
                    .frame(width: TelefamMetrics.topIconTouch, height: TelefamMetrics.topIconTouch)
            }

            Button {
                showComingSoon()
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
        if let convId = viewModel.selectedConversationId,
           let conv = viewModel.conversations.first(where: { $0.id == convId }) {
            chatThreadView(conv)
        } else if viewModel.conversations.isEmpty {
            emptyStateView
        } else {
            List(viewModel.conversations) { conv in
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
                    showComingSoon()
                } label: {
                    navItemLabel(title: "Feeds", active: false, inactiveColor: inactiveColor) {
                        FeedsVectorIcon()
                            .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54)

                Button {
                    showComingSoon()
                } label: {
                    navItemLabel(title: "Profile", active: false, inactiveColor: inactiveColor) {
                        ProfileVectorIcon()
                            .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
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
                showComingSoon()
            } label: {
                navItemLabel(title: "Feeds", active: false, inactiveColor: inactiveColor) {
                    FeedsVectorIcon()
                        .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)

            Button {
                showComingSoon()
            } label: {
                navItemLabel(title: "Profile", active: false, inactiveColor: inactiveColor) {
                    ProfileVectorIcon()
                        .stroke(inactiveColor, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
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

    private func showComingSoon() {
        toastText = "Coming soon"
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            toastText = nil
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
