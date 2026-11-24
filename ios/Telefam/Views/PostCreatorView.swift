import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private struct TelefamVideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { item in
            SentTransferredFile(item.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

private struct TelefamFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 10
    var verticalSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + horizontalSpacing + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, rowWidth)
                totalHeight += rowHeight + verticalSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        maxRowWidth = max(maxRowWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : maxRowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct PostCreatorView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var videoPickerItem: PhotosPickerItem? = nil
    @State private var showSongSheet = false
    @State private var showTagSheet = false
    @State private var showHashtagSheet = false

    private var isDark: Bool { viewModel.isDarkTheme }
    private let brandRed = TelefamColors.crimson

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if viewModel.postUploadStatus == .uploading || viewModel.postUploadStatus == .uploaded {
                VStack(spacing: 4) {
                    HStack {
                        Text(
                            viewModel.postUploadStatus == .uploaded
                                ? "Uploaded"
                                : "Uploading \(viewModel.postUploadProgress)%"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        Spacer()
                    }
                    if viewModel.postUploadStatus == .uploading {
                        ProgressView(value: Double(viewModel.postUploadProgress), total: 100.0)
                            .tint(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(brandRed)
            }

            ZStack {
                TelefamColors.background(isDark: isDark)

                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 22) {
                        ScrollView {
                            primaryStageContent
                                .padding(.vertical, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ScrollView {
                            secondaryControlsContent
                                .padding(.vertical, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 22)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            primaryStageContent
                            secondaryControlsContent
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(brandRed.ignoresSafeArea(edges: .top))
        .telefamSwipeBack {
            viewModel.closePostComposer()
        }
        .onChange(of: photoPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var loaded: [Data] = []
                for item in newItems.prefix(10) {
                    if let d = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(d)
                    }
                }
                photoPickerItems = []
                await viewModel.addPickedPhotoData(loaded)
            }
        }
        .onChange(of: videoPickerItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let vid = try? await item.loadTransferable(type: TelefamVideoTransferable.self) {
                    await viewModel.selectVideoFile(vid.url)
                }
                videoPickerItem = nil
            }
        }
        .sheet(isPresented: $showSongSheet) {
            SongPickerSheetIOS(viewModel: viewModel)
        }
        .sheet(isPresented: $showTagSheet) {
            TagPeopleSheetIOS(viewModel: viewModel)
        }
        .sheet(isPresented: $showHashtagSheet) {
            HashtagPickerSheetIOS(viewModel: viewModel)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    viewModel.closePostComposer()
                } label: {
                    CloseVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .frame(width: 48, height: 48)
                }

                Text("New post")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    Task { await viewModel.sharePost(quality: networkQuality) }
                } label: {
                    Text("Share")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brandRed.opacity(viewModel.canSharePost ? 1.0 : 0.55))
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Color.white.opacity(viewModel.canSharePost ? 1.0 : 0.65))
                        .clipShape(Capsule())
                }
                .disabled(!viewModel.canSharePost)
            }
            .padding(.horizontal, 10)

            HStack(spacing: 10) {
                tabPill(mode: .text, label: "Text") {
                    Text("T")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(viewModel.postMode == .text ? TelefamColors.darkBackground : .white)
                }
                tabPill(mode: .photos, label: "Photos") {
                    PhotosTabVectorIcon()
                        .stroke(
                            viewModel.postMode == .photos ? TelefamColors.darkBackground : .white,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 17, height: 17)
                }
                tabPill(mode: .video, label: "Video") {
                    VideoTabVectorIcon()
                        .stroke(
                            viewModel.postMode == .video ? TelefamColors.darkBackground : .white,
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 17, height: 17)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func tabPill<Icon: View>(
        mode: PostTabModeIOS,
        label: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let selected = viewModel.postMode == mode
        return Button {
            viewModel.postMode = mode
            viewModel.postInlineError = nil
        } label: {
            HStack(spacing: 8) {
                icon()
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selected ? TelefamColors.darkBackground : .white)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(selected ? Color.white : Color.clear)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var primaryStageContent: some View {
        switch viewModel.postMode {
        case .text:
            textCard
        case .photos:
            photosCard
        case .video:
            videoCard
        }
    }

    @ViewBuilder
    private var secondaryControlsContent: some View {
        VStack(spacing: 14) {
            if viewModel.postMode == .text {
                textStyleControls
            } else {
                captionCard
            }
            metadataCard
        }
    }

    private var textCard: some View {
        let activeTheme = POST_IMAGE_THEMES_IOS.first { $0.id == viewModel.postImageThemeId }
        let activeColor = POST_BG_COLORS_IOS.first { $0.hex.caseInsensitiveCompare(viewModel.postBgColorHex) == .orderedSame }
            ?? POST_BG_COLORS_IOS[0]
        let fgColor: Color = {
            if let th = activeTheme { return th.isDarkText ? Color(red: 28/255, green: 30/255, blue: 34/255) : .white }
            return activeColor.isDarkText ? Color(red: 28/255, green: 30/255, blue: 34/255) : .white
        }()

        return ZStack {
            if let th = activeTheme {
                PostThemeArtworkIOS(theme: th)
            } else {
                activeColor.color
            }

            ZStack {
                if viewModel.postTextBody.isEmpty {
                    Text("What's on your mind?")
                        .font(viewModel.postFont.swiftUIFont(size: 24))
                        .foregroundColor(fgColor.opacity(0.74))
                        .multilineTextAlignment(.center)
                }
                TextField(
                    "",
                    text: Binding(
                        get: { viewModel.postTextBody },
                        set: { viewModel.updatePostTextBody($0) }
                    ),
                    axis: .vertical
                )
                .font(viewModel.postFont.swiftUIFont(size: 24))
                .foregroundColor(fgColor)
                .multilineTextAlignment(.center)
                .tint(fgColor)
            }
            .padding(24)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(viewModel.postTextBody.count)/280")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(fgColor.opacity(0.8))
                }
            }
            .padding(16)
        }
        .frame(minHeight: 290, maxHeight: 330)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var textStyleControls: some View {
        let pillBg = TelefamColors.surface(isDark: isDark)
        let borderCol = TelefamColors.border(isDark: isDark)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                paletteToggleButton(
                    label: "Colors",
                    selected: !viewModel.postShowImageThemes
                ) {
                    PaletteVectorIcon()
                        .stroke(!viewModel.postShowImageThemes ? brandRed : TelefamColors.inkSecondary(isDark: isDark), lineWidth: 1.8)
                        .frame(width: 15, height: 15)
                } action: {
                    viewModel.postShowImageThemes = false
                }

                paletteToggleButton(
                    label: "Themes",
                    selected: viewModel.postShowImageThemes
                ) {
                    ImageThemeVectorIcon()
                        .stroke(viewModel.postShowImageThemes ? brandRed : TelefamColors.inkSecondary(isDark: isDark), lineWidth: 1.8)
                        .frame(width: 15, height: 15)
                } action: {
                    viewModel.postShowImageThemes = true
                }
                Spacer()
            }

            if !viewModel.postShowImageThemes {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(POST_BG_COLORS_IOS) { opt in
                            let selected = viewModel.postImageThemeId == nil &&
                                viewModel.postBgColorHex.caseInsensitiveCompare(opt.hex) == .orderedSame
                            Button {
                                viewModel.selectBgColor(opt.hex)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(opt.color)
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Circle().stroke(selected ? Color.white : borderCol, lineWidth: selected ? 2.5 : 1)
                                        )
                                    if selected {
                                        CheckMarkVectorIcon()
                                            .stroke(opt.isDarkText ? Color.black : Color.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                                            .frame(width: 16, height: 16)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(POST_IMAGE_THEMES_IOS) { theme in
                            let selected = viewModel.postImageThemeId == theme.id
                            Button {
                                viewModel.selectImageTheme(theme.id)
                            } label: {
                                ZStack {
                                    PostThemeArtworkIOS(theme: theme)
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle().stroke(selected ? Color.white : borderCol, lineWidth: selected ? 2.5 : 1)
                                        )
                                    if selected {
                                        CheckMarkVectorIcon()
                                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                                            .frame(width: 16, height: 16)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            TelefamFlowLayout(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(PostFontStyleIOS.allCases) { font in
                    let isSelected = viewModel.postFont == font
                    Button {
                        viewModel.postFont = font
                    } label: {
                        HStack(spacing: 6) {
                            Text(font.badge)
                                .font(font.swiftUIFont(size: 13))
                                .foregroundColor(isSelected ? brandRed : TelefamColors.inkPrimary(isDark: isDark))
                            Text(font.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isSelected ? brandRed : TelefamColors.inkPrimary(isDark: isDark))
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(isSelected ? brandRed.opacity(0.14) : pillBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? brandRed : borderCol, lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    private func paletteToggleButton<Icon: View>(
        label: String,
        selected: Bool,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(selected ? brandRed : TelefamColors.inkSecondary(isDark: isDark))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? brandRed.opacity(0.14) : TelefamColors.surface(isDark: isDark))
            .overlay(
                Capsule().stroke(selected ? brandRed : TelefamColors.border(isDark: isDark), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var photosCard: some View {
        let cardBg = isDark ? TelefamColors.darkSurface : TelefamColors.lightSurfaceSubtle
        let borderCol = TelefamColors.border(isDark: isDark)

        if viewModel.postPhotos.isEmpty {
            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                VStack(spacing: 12) {
                    if viewModel.postIsExtractingMedia {
                        ProgressView().tint(brandRed)
                    } else {
                        Circle()
                            .fill(brandRed.opacity(0.16))
                            .frame(width: 58, height: 58)
                            .overlay(
                                PhotosTabVectorIcon()
                                    .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                    .frame(width: 26, height: 26)
                            )
                        Text("Add photos")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                        Text("Up to 10")
                            .font(.system(size: 13))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 290)
                .background(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(borderCol, lineWidth: 1))
                .cornerRadius(20)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.postPhotos) { item in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: item.uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 240)
                                .clipped()
                                .cornerRadius(16)

                            Button {
                                viewModel.removePhoto(id: item.id)
                            } label: {
                                CloseVectorIcon()
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .frame(width: 13, height: 13)
                                    .frame(width: 30, height: 30)
                                    .background(Color.black.opacity(0.65))
                                    .clipShape(Circle())
                            }
                            .padding(8)
                        }
                    }

                    if viewModel.postPhotos.count < 10 {
                        PhotosPicker(
                            selection: $photoPickerItems,
                            maxSelectionCount: max(1, 10 - viewModel.postPhotos.count),
                            matching: .images
                        ) {
                            VStack(spacing: 6) {
                                PlusVectorIcon()
                                    .stroke(brandRed, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                    .frame(width: 24, height: 24)
                                Text("\(viewModel.postPhotos.count)/10")
                                    .font(.system(size: 13))
                                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                            }
                            .frame(width: 110, height: 240)
                            .background(cardBg)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderCol, lineWidth: 1))
                            .cornerRadius(16)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var videoCard: some View {
        let cardBg = isDark ? TelefamColors.darkSurface : TelefamColors.lightSurfaceSubtle
        let borderCol = TelefamColors.border(isDark: isDark)

        if viewModel.postVideoURL == nil {
            PhotosPicker(
                selection: $videoPickerItem,
                matching: .videos
            ) {
                VStack(spacing: 12) {
                    if viewModel.postIsExtractingMedia {
                        ProgressView().tint(brandRed)
                    } else {
                        Circle()
                            .fill(brandRed.opacity(0.16))
                            .frame(width: 58, height: 58)
                            .overlay(
                                ClapperboardVectorIcon()
                                    .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                    .frame(width: 26, height: 26)
                            )
                        Text("Add video")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                        Text(viewModel.postInlineError ?? "Up to 200 MB")
                            .font(.system(size: 13))
                            .foregroundColor(viewModel.postInlineError != nil ? brandRed : TelefamColors.inkSecondary(isDark: isDark))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 290)
                .background(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(borderCol, lineWidth: 1))
                .cornerRadius(20)
            }
        } else {
            VStack(spacing: 12) {
                ZStack {
                    Color.black
                    if let thumb = viewModel.postSelectedThumbImage {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    }
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                viewModel.autoSelectThumbnail()
                            } label: {
                                HStack(spacing: 4) {
                                    AutoSparkleVectorIcon()
                                        .fill(Color.white)
                                        .frame(width: 13, height: 13)
                                    Text("Auto")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Capsule())
                            }

                            Button {
                                viewModel.clearVideo()
                            } label: {
                                CloseVectorIcon()
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .frame(width: 13, height: 13)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.65))
                                    .clipShape(Circle())
                            }
                        }
                        Spacer()
                        HStack {
                            Text("\(formatMs(viewModel.postTrimStartMs)) – \(formatMs(viewModel.postTrimEndMs))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(10)
                            Spacer()
                        }
                    }
                    .padding(10)
                }
                .frame(height: 240)
                .clipped()
                .cornerRadius(20)

                if !viewModel.postVideoFrames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(viewModel.postVideoFrames) { frame in
                                let selected = frame.timestampMs == viewModel.postSelectedThumbMs
                                Button {
                                    viewModel.selectThumbFrame(frame)
                                } label: {
                                    Image(uiImage: frame.uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 62, height: 54)
                                        .clipped()
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selected ? brandRed : borderCol, lineWidth: selected ? 2.5 : 1)
                                        )
                                }
                            }
                        }
                    }
                }

                if viewModel.postVideoDurationMs > 500 {
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Text(formatMs(viewModel.postTrimStartMs))
                                .font(.caption)
                                .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.postTrimStartMs) },
                                    set: { viewModel.updateVideoTrim(startMs: Int64($0), endMs: viewModel.postTrimEndMs) }
                                ),
                                in: 0...Double(max(1000, viewModel.postVideoDurationMs - 500))
                            )
                            .tint(brandRed)
                        }
                        HStack(spacing: 12) {
                            Text(formatMs(viewModel.postTrimEndMs))
                                .font(.caption)
                                .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.postTrimEndMs) },
                                    set: { viewModel.updateVideoTrim(startMs: viewModel.postTrimStartMs, endMs: Int64($0)) }
                                ),
                                in: Double(min(viewModel.postTrimStartMs + 500, viewModel.postVideoDurationMs))...Double(max(1000, viewModel.postVideoDurationMs))
                            )
                            .tint(brandRed)
                        }
                    }
                }

                HStack {
                    if viewModel.postMuteOriginalAudio {
                        VolumeOffVectorIcon()
                            .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                    } else {
                        VolumeOnVectorIcon()
                            .stroke(TelefamColors.inkPrimary(isDark: isDark), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                    }
                    Text("Mute audio")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.postMuteOriginalAudio },
                        set: { _ in viewModel.toggleMuteAudio() }
                    ))
                    .labelsHidden()
                    .tint(brandRed)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(cardBg)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderCol, lineWidth: 1))
                .cornerRadius(14)
            }
        }
    }

    private var captionCard: some View {
        let cardBg = isDark ? TelefamColors.darkSurface : TelefamColors.lightSurfaceSubtle
        let borderCol = TelefamColors.border(isDark: isDark)

        return ZStack(alignment: .topLeading) {
            if viewModel.postCaption.isEmpty {
                Text("Write a caption...")
                    .font(.system(size: 15))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    .padding(14)
            }
            VStack(alignment: .trailing, spacing: 6) {
                TextField(
                    "",
                    text: Binding(
                        get: { viewModel.postCaption },
                        set: { viewModel.updatePostCaption($0) }
                    ),
                    axis: .vertical
                )
                .font(.system(size: 15))
                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                .frame(minHeight: 72, alignment: .topLeading)

                Text("\(viewModel.postCaption.count)/2200")
                    .font(.system(size: 12))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
            }
            .padding(14)
        }
        .background(cardBg)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderCol, lineWidth: 1))
        .cornerRadius(16)
    }

    private var metadataCard: some View {
        let cardBg = isDark ? TelefamColors.darkSurface : TelefamColors.lightSurfaceSubtle
        let borderCol = TelefamColors.border(isDark: isDark)

        return VStack(spacing: 0) {
            Button {
                showSongSheet = true
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(brandRed.opacity(0.16))
                        .frame(width: 34, height: 34)
                        .overlay(
                            MusicNoteVectorIcon()
                                .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                .frame(width: 17, height: 17)
                        )
                    Text(viewModel.postSelectedSong?.title ?? "Song")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                        .lineLimit(1)
                    Spacer()

                    if let song = viewModel.postSelectedSong, !song.preview_url.isEmpty {
                        let playing = viewModel.postIsPlayingSongPreview && viewModel.postPreviewingTrackId == song.track_id
                        Button {
                            viewModel.toggleSongPreview(song)
                        } label: {
                            Group {
                                if playing {
                                    PauseBarsVectorIcon().fill(Color.white)
                                } else {
                                    PlayTriangleVectorIcon().fill(Color.white)
                                }
                            }
                            .frame(width: 14, height: 14)
                            .frame(width: 34, height: 34)
                            .background(brandRed)
                            .clipShape(Circle())
                        }
                    } else {
                        Text("Add")
                            .font(.system(size: 14))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                        ChevronRightVectorIcon()
                            .stroke(TelefamColors.inkSecondary(isDark: isDark), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
            }

            Rectangle().fill(borderCol).frame(height: 1)

            Button {
                showTagSheet = true
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(brandRed.opacity(0.16))
                        .frame(width: 34, height: 34)
                        .overlay(
                            ContactsOutlineVectorIcon()
                                .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                                .frame(width: 17, height: 17)
                        )
                    Text("Tag people")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    Spacer()
                    Text(viewModel.postTaggedContacts.isEmpty ? "Add" : "\(viewModel.postTaggedContacts.count)")
                        .font(.system(size: 14))
                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    ChevronRightVectorIcon()
                        .stroke(TelefamColors.inkSecondary(isDark: isDark), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 14, height: 14)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
            }

            if viewModel.postMode != .text {
                Rectangle().fill(borderCol).frame(height: 1)

                Button {
                    showHashtagSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(brandRed.opacity(0.16))
                            .frame(width: 34, height: 34)
                            .overlay(
                                HashtagVectorIcon()
                                    .stroke(brandRed, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .frame(width: 17, height: 17)
                            )
                        Text("Hashtags")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                        Spacer()
                        Text(viewModel.postSelectedHashtags.isEmpty ? "Add" : "\(viewModel.postSelectedHashtags.count)")
                            .font(.system(size: 14))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                        ChevronRightVectorIcon()
                            .stroke(TelefamColors.inkSecondary(isDark: isDark), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 14, height: 14)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 54)
                }
            }
        }
        .background(cardBg)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(borderCol, lineWidth: 1))
        .cornerRadius(16)
    }

    private func formatMs(_ ms: Int64) -> String {
        let secs = max(0, Int(ms / 1000))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

private struct SongPickerSheetIOS: View {
    @ObservedObject var viewModel: TelefamViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                TextField(
                    "Search songs or artists",
                    text: Binding(
                        get: { viewModel.postSongQuery },
                        set: { viewModel.searchSongs($0) }
                    )
                )
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(TelefamColors.surface(isDark: viewModel.isDarkTheme))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TelefamColors.border(isDark: viewModel.isDarkTheme), lineWidth: 1))
                .cornerRadius(12)
                .padding(.horizontal, 16)

                if viewModel.postIsSearchingSongs && viewModel.postSongResults.isEmpty {
                    Spacer()
                    ProgressView().tint(TelefamColors.crimson)
                    Spacer()
                } else {
                    List(viewModel.postSongResults) { track in
                        let playing = viewModel.postPreviewingTrackId == track.track_id && viewModel.postIsPlayingSongPreview
                        HStack(spacing: 12) {
                            Button {
                                viewModel.selectSong(track)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(TelefamColors.crimson.opacity(0.16))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            MusicNoteVectorIcon()
                                                .stroke(TelefamColors.crimson, lineWidth: 1.9)
                                                .frame(width: 18, height: 18)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(TelefamColors.inkPrimary(isDark: viewModel.isDarkTheme))
                                            .lineLimit(1)
                                        Text("\(track.artist) · \(track.duration_sec)s")
                                            .font(.system(size: 13))
                                            .foregroundColor(TelefamColors.inkSecondary(isDark: viewModel.isDarkTheme))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            if !track.preview_url.isEmpty {
                                Button {
                                    viewModel.toggleSongPreview(track)
                                } label: {
                                    Group {
                                        if playing {
                                            PauseBarsVectorIcon().fill(Color.white)
                                        } else {
                                            PlayTriangleVectorIcon().fill(Color.white)
                                        }
                                    }
                                    .frame(width: 15, height: 15)
                                    .frame(width: 42, height: 42)
                                    .background(TelefamColors.crimson)
                                    .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Song")
            .toolbar {
                if viewModel.postSelectedSong != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") {
                            viewModel.selectSong(nil)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TagPeopleSheetIOS: View {
    @ObservedObject var viewModel: TelefamViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ContactUserItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return viewModel.cachedContacts }
        return viewModel.cachedContacts.filter {
            $0.full_name.lowercased().contains(q) || $0.username.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                TextField("Search people", text: $query)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(TelefamColors.surface(isDark: viewModel.isDarkTheme))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(TelefamColors.border(isDark: viewModel.isDarkTheme), lineWidth: 1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)

                List(filtered) { contact in
                    let isTagged = viewModel.postTaggedContacts.contains { $0.user_id == contact.user_id }
                    Button {
                        viewModel.toggleTagContact(contact)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(TelefamColors.crimson.opacity(0.16))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(contact.full_name.prefix(2)).uppercased())
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(TelefamColors.crimson)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.full_name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(TelefamColors.inkPrimary(isDark: viewModel.isDarkTheme))
                                Text("@\(contact.username)")
                                    .font(.system(size: 13))
                                    .foregroundColor(TelefamColors.inkSecondary(isDark: viewModel.isDarkTheme))
                            }
                            Spacer()
                            if isTagged {
                                Circle()
                                    .fill(TelefamColors.crimson)
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        CheckMarkVectorIcon()
                                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                            .frame(width: 14, height: 14)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Tag people")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HashtagPickerSheetIOS: View {
    @ObservedObject var viewModel: TelefamViewModel
    @Environment(\.dismiss) private var dismiss

    private var sanitizedQuery: String {
        viewModel.postHashtagQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.postSelectedHashtags.isEmpty {
                    TelefamFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(viewModel.postSelectedHashtags, id: \.self) { tag in
                            Button {
                                viewModel.toggleHashtag(tag)
                            } label: {
                                Text("#\(tag) ×")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(TelefamColors.crimson)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(TelefamColors.crimson.opacity(0.15))
                                    .overlay(Capsule().stroke(TelefamColors.crimson, lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                TextField(
                    "Search hashtags",
                    text: Binding(
                        get: { viewModel.postHashtagQuery },
                        set: { viewModel.searchHashtags($0) }
                    )
                )
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(TelefamColors.surface(isDark: viewModel.isDarkTheme))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TelefamColors.border(isDark: viewModel.isDarkTheme), lineWidth: 1))
                .cornerRadius(12)
                .padding(.horizontal, 16)

                if !sanitizedQuery.isEmpty && !viewModel.postHashtagResults.contains(where: { $0.tag == sanitizedQuery }) {
                    Button {
                        viewModel.toggleHashtag(sanitizedQuery)
                    } label: {
                        HStack {
                            Text("#\(sanitizedQuery)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(TelefamColors.crimson)
                            Spacer()
                            Text("Add")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(TelefamColors.crimson)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(TelefamColors.crimson.opacity(0.12))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                }

                List(viewModel.postHashtagResults) { item in
                    let active = viewModel.postSelectedHashtags.contains(item.tag)
                    Button {
                        viewModel.toggleHashtag(item.tag)
                    } label: {
                        HStack {
                            Text("#\(item.tag)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(active ? TelefamColors.crimson : TelefamColors.inkPrimary(isDark: viewModel.isDarkTheme))
                            Spacer()
                            Text("\(item.post_count) posts")
                                .font(.system(size: 13))
                                .foregroundColor(TelefamColors.inkSecondary(isDark: viewModel.isDarkTheme))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Hashtags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
