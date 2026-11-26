import SwiftUI

struct CommentsComingSoonSheetIOS: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 45/255, blue: 85/255).opacity(0.16))
                    .frame(width: 68, height: 68)
                FeedCommentBubbleVectorIcon()
                    .fill(Color(red: 1.0, green: 45/255, blue: 85/255))
                    .frame(width: 28, height: 28)
            }
            Text("Comments Coming Soon")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("Video comments are not open yet.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.14))
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color(red: 18/255, green: 19/255, blue: 22/255).ignoresSafeArea())
        .presentationDetents([.height(290)])
    }
}

struct FeedVideoOptionsSheetIOS: View {
    let video: FeedVideoItem
    let onReport: () -> Void
    let onRepost: () -> Void
    let onBlockCreator: () -> Void
    let onMuteCreator: () -> Void
    let onNotInterested: () -> Void
    let onOwnerEdit: () -> Void
    let onOwnerMarkPrivate: () -> Void
    let onOwnerVisibility: () -> Void
    let onOwnerDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if video.is_owner {
                optionRow(title: "Edit details") {
                    EditPencilVectorIcon().stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                } action: {
                    dismiss()
                    onOwnerEdit()
                }
                optionRow(title: video.visibility == "private" ? "Private" : "Mark as private") {
                    LockVectorIcon().stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                } action: {
                    dismiss()
                    onOwnerMarkPrivate()
                }
                optionRow(title: "Change visibility") {
                    VisibilityEyeVectorIcon().stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                } action: {
                    dismiss()
                    onOwnerVisibility()
                }
                optionRow(title: "Delete video", tint: Color(red: 1.0, green: 45/255, blue: 85/255)) {
                    CloseVectorIcon().stroke(Color(red: 1.0, green: 45/255, blue: 85/255), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                } action: {
                    dismiss()
                    onOwnerDelete()
                }
            } else {
                optionRow(title: video.is_reposted ? "Remove repost" : "Repost") {
                    RepostVectorIcon().stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                } action: {
                    dismiss()
                    onRepost()
                }
                optionRow(title: "Not interested") {
                    CloseVectorIcon().stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                } action: {
                    dismiss()
                    onNotInterested()
                }
                optionRow(title: "Mute @\(video.creator_username)") {
                    VolumeOffVectorIcon().stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                } action: {
                    dismiss()
                    onMuteCreator()
                }
                optionRow(title: "Block @\(video.creator_username)", tint: Color(red: 1.0, green: 45/255, blue: 85/255)) {
                    BlockCircleVectorIcon().stroke(Color(red: 1.0, green: 45/255, blue: 85/255), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                } action: {
                    dismiss()
                    onBlockCreator()
                }
                optionRow(title: "Report video", tint: Color(red: 1.0, green: 45/255, blue: 85/255)) {
                    FlagReportVectorIcon().stroke(Color(red: 1.0, green: 45/255, blue: 85/255), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                } action: {
                    dismiss()
                    onReport()
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 18/255, green: 19/255, blue: 22/255).ignoresSafeArea())
        .presentationDetents([.medium])
    }

    private func optionRow<Icon: View>(
        title: String,
        tint: Color = .white,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 22, height: 22)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(tint)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
    }
}

struct ReportVideoSheetIOS: View {
    let onSubmit: (FeedReportReasonIOS, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: FeedReportReasonIOS? = nil
    @State private var details: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let chosen = selectedReason {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(chosen.label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        TextEditor(text: $details)
                            .scrollContentBackground(.hidden)
                            .foregroundColor(.white)
                            .padding(10)
                            .frame(height: 120)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        Button("Submit") {
                            onSubmit(chosen, details)
                            dismiss()
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(red: 1.0, green: 45/255, blue: 85/255))
                        .cornerRadius(12)
                    }
                    .padding(18)
                } else {
                    List(FeedReportReasonIOS.allCases) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason.label)
                                    .foregroundColor(.white)
                                Spacer()
                                ChevronRightVectorIcon()
                                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                    .frame(width: 14, height: 14)
                            }
                            .frame(minHeight: 44)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                Spacer()
            }
            .background(Color(red: 18/255, green: 19/255, blue: 22/255).ignoresSafeArea())
            .navigationTitle("Report video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedReason == nil ? "Close" : "Back") {
                        if selectedReason != nil {
                            selectedReason = nil
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct OwnerEditDetailsSheetIOS: View {
    let initialTitle: String
    let initialDescription: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var descriptionText: String

    init(initialTitle: String, initialDescription: String, onSave: @escaping (String, String) -> Void) {
        self.initialTitle = initialTitle
        self.initialDescription = initialDescription
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _descriptionText = State(initialValue: initialDescription)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Title", text: $title)
                    .padding(12)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                TextEditor(text: $descriptionText)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .padding(10)
                    .frame(height: 140)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                Button("Save") {
                    onSave(title, descriptionText)
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(TelefamColors.crimson)
                .cornerRadius(12)
                Spacer()
            }
            .padding(18)
            .background(Color(red: 18/255, green: 19/255, blue: 22/255).ignoresSafeArea())
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct OwnerVisibilitySheetIOS: View {
    let currentVisibility: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options = [
        ("public", "Public"),
        ("followers", "Followers only"),
        ("private", "Private")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change visibility")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 6)
            ForEach(options, id: \.0) { key, label in
                Button {
                    onSelect(key)
                    dismiss()
                } label: {
                    HStack {
                        Text(label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        if currentVisibility == key {
                            CheckMarkVectorIcon()
                                .stroke(TelefamColors.crimson, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(Color(red: 18/255, green: 19/255, blue: 22/255).ignoresSafeArea())
        .presentationDetents([.height(290)])
    }
}

struct SavedVideosSheetIOS: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingSavedVideos && viewModel.savedVideos.isEmpty {
                    ProgressView().tint(TelefamColors.crimson)
                } else if viewModel.savedVideos.isEmpty {
                    Text("No saved videos")
                        .foregroundColor(TelefamColors.inkSecondary(isDark: viewModel.isDarkTheme))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 4)], spacing: 4) {
                            ForEach(Array(viewModel.savedVideos.enumerated()), id: \.element.video_id) { idx, vid in
                                Button {
                                    dismiss()
                                    viewModel.openModalFeedPlayer(videos: viewModel.savedVideos, initialIndex: idx, title: "Saved videos")
                                } label: {
                                    FeedThumbnailGridCellIOS(video: vid, resolveURL: { viewModel.api.resolveMediaURL($0) })
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            }
            .background(TelefamColors.background(isDark: viewModel.isDarkTheme))
            .navigationTitle("Saved videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await viewModel.loadSavedVideos(quality: networkQuality)
        }
    }
}

struct SafetyPreferencesSheetIOS: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Muted") {
                    if viewModel.safetyPreferences.muted_users.isEmpty {
                        Text("None")
                            .foregroundColor(TelefamColors.inkSecondary(isDark: viewModel.isDarkTheme))
                    } else {
                        ForEach(viewModel.safetyPreferences.muted_users) { u in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(u.full_name.isEmpty ? u.username : u.full_name).font(.subheadline.weight(.semibold))
                                    Text("@\(u.username)").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Unmute") {
                                    Task { await viewModel.unmuteUserFromSafety(u.user_id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section("Blocked") {
                    if viewModel.safetyPreferences.blocked_users.isEmpty {
                        Text("None")
                            .foregroundColor(TelefamColors.inkSecondary(isDark: viewModel.isDarkTheme))
                    } else {
                        ForEach(viewModel.safetyPreferences.blocked_users) { u in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(u.full_name.isEmpty ? u.username : u.full_name).font(.subheadline.weight(.semibold))
                                    Text("@\(u.username)").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Unblock") {
                                    Task { await viewModel.unblockUserFromSafety(u.user_id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Muted & Blocked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await viewModel.loadSafetyPreferences(quality: networkQuality)
        }
    }
}
