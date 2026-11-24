import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @ObservedObject var viewModel: TelefamViewModel
    @ObservedObject var network: NetworkMonitor

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var showDobPicker = false

    private var isDark: Bool { viewModel.isDarkTheme }
    private let brandRed = TelefamColors.crimson

    private var maxDobDate: Date {
        Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
    }

    private var selectedCountry: CountryCodeOption {
        SUPPORTED_COUNTRIES_IOS.first(where: { $0.iso == viewModel.countryIso }) ?? SUPPORTED_COUNTRIES_IOS[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Crimson Header matching Android
            ZStack {
                HStack {
                    Button {
                        viewModel.signOut()
                    } label: {
                        ArrowLeftVectorIcon()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                            .frame(width: TelefamMetrics.topIconTouch, height: TelefamMetrics.topIconTouch)
                    }
                    Spacer()
                }
                VStack(spacing: 2) {
                    Text("Profile Setup")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Tell us about yourself")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(brandRed)

            // Rounded Sheet Body
            ScrollView {
                VStack(spacing: 16) {
                    // Avatar Picker
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let data = viewModel.avatarJPEGData, let uiImg = UIImage(data: data) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(brandRed, lineWidth: 2))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(brandRed.opacity(isDark ? 0.16 : 0.08))
                                        .frame(width: 96, height: 96)
                                    Circle()
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.8, dash: [6, 5]))
                                        .foregroundColor(brandRed.opacity(0.7))
                                        .frame(width: 96, height: 96)
                                    CameraVectorIcon()
                                        .fill(brandRed, style: FillStyle(eoFill: true))
                                        .frame(width: 34, height: 34)
                                }
                            }
                            Circle()
                                .fill(brandRed)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    PlusVectorIcon()
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                                        .frame(width: 15, height: 15)
                                )
                                .overlay(Circle().stroke(TelefamColors.surface(isDark: isDark), lineWidth: 2))
                        }
                        .frame(width: 102, height: 102)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 4) {
                        Text("Upload Profile Photo")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                        Text("Add a clear photo to help your\nfriends recognize you.")
                            .font(.system(size: 13))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                            .multilineTextAlignment(.center)
                    }

                    // Full Name
                    fieldBlock(label: "Full Name", icon: {
                        ProfileVectorIcon()
                            .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }) {
                        TextField("Enter your full name", text: $viewModel.fullName)
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                            .textInputAutocapitalization(.words)
                    }

                    // Username
                    fieldBlock(label: "Username", icon: {
                        AtVectorIcon()
                            .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    }) {
                        TextField("Choose a username", text: $viewModel.username)
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    // Phone Number
                    VStack(alignment: .leading, spacing: 6) {
                        labelRow(title: "Phone Number") {
                            PhoneVectorIcon()
                                .stroke(brandRed, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                        HStack(spacing: 0) {
                            Menu {
                                ForEach(SUPPORTED_COUNTRIES_IOS) { country in
                                    Button {
                                        viewModel.countryIso = country.iso
                                    } label: {
                                        Text("\(country.flag) \(country.name) (\(country.dialCode))")
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCountry.flag).font(.system(size: 20))
                                    ChevronDownVectorIcon()
                                        .stroke(TelefamColors.inkSecondary(isDark: isDark), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 54)
                            }

                            Rectangle()
                                .fill(TelefamColors.border(isDark: isDark))
                                .frame(width: 1, height: 32)

                            TextField("\(selectedCountry.dialCode)  Enter your phone number", text: $viewModel.phoneNumber)
                                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                                .keyboardType(.phonePad)
                                .padding(.horizontal, 12)
                                .frame(height: 54)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                                .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                        )
                    }

                    // Gender
                    VStack(alignment: .leading, spacing: 6) {
                        labelRow(title: "Gender") {
                            ContactsOutlineVectorIcon()
                                .stroke(brandRed, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        }
                        Menu {
                            Button("Male") { viewModel.gender = "male" }
                            Button("Female") { viewModel.gender = "female" }
                            Button("Non-binary") { viewModel.gender = "non_binary" }
                            Button("Prefer not to say") { viewModel.gender = "prefer_not_to_say" }
                        } label: {
                            HStack {
                                Text(genderDisplayText)
                                    .foregroundColor(viewModel.gender.isEmpty ? TelefamColors.inkSecondary(isDark: isDark) : TelefamColors.inkPrimary(isDark: isDark))
                                Spacer()
                                ChevronDownVectorIcon()
                                    .stroke(TelefamColors.inkSecondary(isDark: isDark), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                    .frame(width: 18, height: 18)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .overlay(
                                RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                                    .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                            )
                        }
                    }

                    // Date of Birth (13+ only)
                    VStack(alignment: .leading, spacing: 6) {
                        labelRow(title: "Date of Birth") {
                            CalendarVectorIcon()
                                .stroke(brandRed, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                        Button {
                            showDobPicker = true
                        } label: {
                            HStack {
                                Text(viewModel.hasSelectedDob ? formattedDob : "Select date of birth")
                                    .foregroundColor(viewModel.hasSelectedDob ? TelefamColors.inkPrimary(isDark: isDark) : TelefamColors.inkSecondary(isDark: isDark))
                                Spacer()
                                ChevronDownVectorIcon()
                                    .stroke(TelefamColors.inkSecondary(isDark: isDark), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                    .frame(width: 18, height: 18)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .overlay(
                                RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                                    .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                            )
                        }
                    }

                    // Location
                    fieldBlock(label: "Location", icon: {
                        LocationPinVectorIcon()
                            .stroke(brandRed, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }) {
                        TextField("City, Country", text: $viewModel.locationText)
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    }

                    // Bio
                    VStack(alignment: .leading, spacing: 6) {
                        labelRow(title: "Bio") {
                            ChatOutlineVectorIcon()
                                .stroke(brandRed, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                        ZStack(alignment: .bottomTrailing) {
                            TextEditor(text: Binding(
                                get: { viewModel.bioText },
                                set: { viewModel.bioText = String($0.prefix(150)) }
                            ))
                            .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                            .frame(height: 112)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            if viewModel.bioText.isEmpty {
                                Text("Tell us something about yourself…")
                                    .font(.system(size: 15))
                                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                            Text("\(viewModel.bioText.count)/150")
                                .font(.caption2)
                                .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                                .padding(10)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                                .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                        )
                    }

                    if let err = viewModel.profileErrorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(brandRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await viewModel.submitProfileSetup(quality: network.quality) }
                    } label: {
                        Group {
                            if viewModel.isSubmittingProfile {
                                ProgressView().tint(.white)
                            } else {
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: TelefamMetrics.continueButtonHeight)
                        .background(brandRed)
                        .cornerRadius(TelefamMetrics.authButtonRadius)
                    }
                    .disabled(viewModel.isSubmittingProfile)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(TelefamColors.surface(isDark: isDark))
            .clipShape(RoundedRectangleShapeCompat(radius: 24))
        }
        .background(brandRed.ignoresSafeArea(edges: .top))
        .telefamSwipeBack { viewModel.signOut() }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   img.size.width > 0, img.size.height > 0 {
                    pendingCropImage = img
                }
            }
        }
        .sheet(isPresented: $showDobPicker) {
            NavigationStack {
                VStack {
                    DatePicker(
                        "Date of Birth",
                        selection: $viewModel.birthDate,
                        in: ...maxDobDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    Spacer()
                }
                .navigationTitle("Date of Birth")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            viewModel.hasSelectedDob = true
                            showDobPicker = false
                        }
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { pendingCropImage.map { IdentifiableImage(image: $0) } },
            set: { if $0 == nil { pendingCropImage = nil } }
        )) { wrapper in
            PhotoCropSheet(source: wrapper.image, brandRed: brandRed) { jpegData in
                pendingCropImage = nil
                Task { await viewModel.setCroppedAvatar(jpegData: jpegData, quality: network.quality) }
            } onCancel: {
                pendingCropImage = nil
            }
        }
    }

    private var genderDisplayText: String {
        switch viewModel.gender {
        case "male": return "Male"
        case "female": return "Female"
        case "non_binary": return "Non-binary"
        case "prefer_not_to_say": return "Prefer not to say"
        default: return "Select gender"
        }
    }

    private var formattedDob: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: viewModel.birthDate)
    }

    private func labelRow<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 8) {
            icon()
                .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
        }
    }

    private func fieldBlock<Icon: View, Content: View>(
        label: String,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow(title: label, icon: icon)
            content()
                .padding(.horizontal, 14)
                .frame(height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                        .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
                )
        }
    }
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct RoundedRectangleShapeCompat: Shape {
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

private struct PhotoCropSheet: View {
    let source: UIImage
    let brandRed: Color
    let onApply: (Data) -> Void
    let onCancel: () -> Void

    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    Color.black
                    Image(uiImage: source)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(zoom)
                        .offset(offset)
                        .frame(width: 260, height: 260)
                        .clipped()
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 236, height: 236)
                }
                .frame(width: 260, height: 260)
                .cornerRadius(14)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )

                Slider(value: $zoom, in: 1.0...3.0)
                    .tint(brandRed)
                    .padding(.horizontal, 32)
            }
            .navigationTitle("Adjust Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard source.size.width > 0, source.size.height > 0 else {
                            onCancel()
                            return
                        }
                        let outSize = CGSize(width: 512, height: 512)
                        let renderer = UIGraphicsImageRenderer(size: outSize)
                        let cropped = renderer.image { _ in
                            let baseScale = max(outSize.width / source.size.width, outSize.height / source.size.height) * min(max(zoom, 1.0), 4.0)
                            let drawW = source.size.width * baseScale
                            let drawH = source.size.height * baseScale
                            let dx = (offset.width / 260.0) * outSize.width
                            let dy = (offset.height / 260.0) * outSize.height
                            let origin = CGPoint(
                                x: (outSize.width - drawW) / 2.0 + dx,
                                y: (outSize.height - drawH) / 2.0 + dy
                            )
                            source.draw(in: CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))
                        }
                        if let jpeg = cropped.jpegData(compressionQuality: 0.9) {
                            onApply(jpeg)
                        }
                    }
                }
            }
        }
    }
}
