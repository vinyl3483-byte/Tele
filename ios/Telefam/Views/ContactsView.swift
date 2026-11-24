import SwiftUI

struct ContactsTopBarView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality

    private var isDark: Bool { viewModel.isDarkTheme }
    private let brandRed = TelefamColors.crimson

    private var searchBg: Color {
        isDark ? TelefamColors.darkContactsSearch : TelefamColors.crimsonDark
    }

    private var pillBg: Color {
        isDark ? TelefamColors.darkContactsPill : TelefamColors.crimsonDark
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    SearchVectorIcon()
                        .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 18, height: 18)

                    TextField(
                        "",
                        text: Binding(
                            get: { viewModel.contactSearchQuery },
                            set: { viewModel.updateContactSearch($0, quality: networkQuality) }
                        ),
                        prompt: Text("Search by name or username")
                            .foregroundColor(.white.opacity(0.72))
                    )
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                }
                .padding(.horizontal, 14)
                .frame(height: TelefamMetrics.searchBarHeight)
                .background(searchBg)
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
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ContactFilterIOS.allCases) { filter in
                        let selected = viewModel.contactFilter == filter
                        Button {
                            viewModel.selectContactFilter(filter, quality: networkQuality)
                        } label: {
                            Text(filter.title)
                                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                                .foregroundColor(selected ? TelefamColors.lightInkPrimary : .white)
                                .padding(.horizontal, 18)
                                .frame(height: TelefamMetrics.filterPillHeight)
                                .background(selected ? Color.white : Color.clear)
                                .cornerRadius(TelefamMetrics.filterPillRadius)
                        }
                        .frame(minHeight: TelefamMetrics.minTouchSize)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(brandRed)
    }
}

struct ContactsContentView: View {
    @ObservedObject var viewModel: TelefamViewModel
    let networkQuality: TelefamNetworkQuality
    let isRegularWidth: Bool
    let onBottomBarVisibilityChange: (Bool) -> Void

    @State private var lastOffsetY: CGFloat = 0
    @State private var scrollStopTask: Task<Void, Never>?

    private var isDark: Bool { viewModel.isDarkTheme }
    private let brandRed = TelefamColors.crimson

    var body: some View {
        let contacts = viewModel.filteredContacts
        ZStack {
            TelefamColors.background(isDark: isDark).ignoresSafeArea()

            if viewModel.isLoadingContacts && contacts.isEmpty {
                ProgressView()
                    .tint(brandRed)
            } else if contacts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    Spacer()
                    HStack {
                        Spacer()
                        Text("No contacts found")
                            .font(.system(size: 15))
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !isRegularWidth {
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: ContactsScrollOffsetKey.self,
                                        value: geo.frame(in: .named("contactsScrollSpace")).minY
                                    )
                            }
                            .frame(height: 0)
                        }

                        sectionHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        if isRegularWidth {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(contacts) { contact in
                                    contactCard(contact)
                                        .onAppear {
                                            if contact.user_id == contacts.last?.user_id,
                                               viewModel.hasMoreContacts,
                                               !viewModel.isLoadingContacts {
                                                Task {
                                                    await viewModel.refreshContacts(reset: false, quality: networkQuality)
                                                }
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(contacts) { contact in
                                    contactRow(contact)
                                        .onAppear {
                                            if contact.user_id == contacts.last?.user_id,
                                               viewModel.hasMoreContacts,
                                               !viewModel.isLoadingContacts {
                                                Task {
                                                    await viewModel.refreshContacts(reset: false, quality: networkQuality)
                                                }
                                            }
                                        }
                                }
                            }
                            .padding(.bottom, 84)
                        }

                        if viewModel.isLoadingContacts {
                            HStack {
                                Spacer()
                                ProgressView().tint(brandRed)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                    }
                }
                .coordinateSpace(name: "contactsScrollSpace")
                .onPreferenceChange(ContactsScrollOffsetKey.self) { newY in
                    guard !isRegularWidth else { return }
                    let delta = newY - lastOffsetY
                    if delta < -6 {
                        onBottomBarVisibilityChange(false)
                    } else if delta > 6 {
                        onBottomBarVisibilityChange(true)
                    }
                    lastOffsetY = newY
                    scrollStopTask?.cancel()
                    scrollStopTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        onBottomBarVisibilityChange(true)
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        Text(viewModel.contactFilter.title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
    }

    private func contactRow(_ contact: ContactUserItem) -> some View {
        HStack(spacing: 14) {
            initialsAvatar(contact.full_name)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.full_name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .lineLimit(1)
                Text(handleLocation(contact))
                    .font(.system(size: 13))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            relationshipButton(contact)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func contactCard(_ contact: ContactUserItem) -> some View {
        HStack(spacing: 12) {
            initialsAvatar(contact.full_name)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.full_name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .lineLimit(1)
                Text(handleLocation(contact))
                    .font(.system(size: 13))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            relationshipButton(contact)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(TelefamColors.surface(isDark: isDark))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private func initialsAvatar(_ fullName: String) -> some View {
        let bg = isDark
            ? Color(red: 0.086, green: 0.169, blue: 0.239)
            : Color(red: 0.918, green: 0.949, blue: 0.980)
        let fg = isDark
            ? Color(red: 0.373, green: 0.659, blue: 0.910)
            : Color(red: 0.114, green: 0.306, blue: 0.847)

        return Circle()
            .fill(bg)
            .frame(width: 48, height: 48)
            .overlay(
                Text(computeInitials(fullName))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(fg)
            )
    }

    @ViewBuilder
    private func relationshipButton(_ contact: ContactUserItem) -> some View {
        let friendsFg = isDark ? Color(red: 0.878, green: 0.322, blue: 0.322) : brandRed
        let friendsBorder = isDark ? Color(red: 0.490, green: 0.137, blue: 0.137) : brandRed.opacity(0.65)
        let friendsBg = isDark ? Color(red: 0.118, green: 0.075, blue: 0.082) : Color(red: 1.0, green: 0.961, blue: 0.961)
        let cardBorder = TelefamColors.border(isDark: isDark)

        Button {
            Task { await viewModel.toggleFollow(contact, quality: networkQuality) }
        } label: {
            switch contact.relationship {
            case "friends":
                HStack(spacing: 7) {
                    FriendsVectorIcon()
                        .stroke(friendsFg, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16)
                    Text("Friends")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(friendsFg)
                }
                .padding(.horizontal, 16)
                .frame(height: TelefamMetrics.actionPillHeight)
                .background(friendsBg)
                .overlay(
                    RoundedRectangle(cornerRadius: TelefamMetrics.actionPillRadius)
                        .stroke(friendsBorder, lineWidth: 1)
                )
                .cornerRadius(TelefamMetrics.actionPillRadius)
            case "following":
                Text("Following")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    .padding(.horizontal, 16)
                    .frame(height: TelefamMetrics.actionPillHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: TelefamMetrics.actionPillRadius)
                            .stroke(cardBorder, lineWidth: 1)
                    )
                    .cornerRadius(TelefamMetrics.actionPillRadius)
            case "follow_back":
                HStack(spacing: 6) {
                    PersonAddVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16)
                    Text("Follow back")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .frame(height: TelefamMetrics.actionPillHeight)
                .background(brandRed)
                .cornerRadius(TelefamMetrics.actionPillRadius)
            default:
                HStack(spacing: 6) {
                    PersonAddVectorIcon()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16)
                    Text("Follow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .frame(height: TelefamMetrics.actionPillHeight)
                .background(brandRed)
                .cornerRadius(TelefamMetrics.actionPillRadius)
            }
        }
        .frame(minHeight: TelefamMetrics.minTouchSize)
    }

    private func handleLocation(_ contact: ContactUserItem) -> String {
        let handle = "@\(contact.username)"
        let loc = contact.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return loc.isEmpty ? handle : "\(handle) · \(loc)"
    }

    private func computeInitials(_ fullName: String) -> String {
        let parts = fullName.split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first {
            return String([a, b]).uppercased()
        }
        if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

private struct ContactsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PersonAddVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 16 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 19 * sy))
        p.addCurve(to: CGPoint(x: 12 * sx, y: 15 * sy), control1: CGPoint(x: 16 * sx, y: 16.79 * sy), control2: CGPoint(x: 14.21 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 1 * sx, y: 19 * sy), control1: CGPoint(x: 2.79 * sx, y: 15 * sy), control2: CGPoint(x: 1 * sx, y: 16.79 * sy))
        p.addLine(to: CGPoint(x: 1 * sx, y: 21 * sy))
        p.addEllipse(in: CGRect(x: 4.5 * sx, y: 3 * sy, width: 8 * sx, height: 8 * sy))
        p.move(to: CGPoint(x: 20 * sx, y: 8 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 14 * sy))
        p.move(to: CGPoint(x: 23 * sx, y: 11 * sy))
        p.addLine(to: CGPoint(x: 17 * sx, y: 11 * sy))
        return p
    }
}

private struct FriendsVectorIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 16 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 16 * sx, y: 19 * sy))
        p.addCurve(to: CGPoint(x: 12 * sx, y: 15 * sy), control1: CGPoint(x: 16 * sx, y: 16.79 * sy), control2: CGPoint(x: 14.21 * sx, y: 15 * sy))
        p.addLine(to: CGPoint(x: 6 * sx, y: 15 * sy))
        p.addCurve(to: CGPoint(x: 2 * sx, y: 19 * sy), control1: CGPoint(x: 3.79 * sx, y: 15 * sy), control2: CGPoint(x: 2 * sx, y: 16.79 * sy))
        p.addLine(to: CGPoint(x: 2 * sx, y: 21 * sy))
        p.addEllipse(in: CGRect(x: 5 * sx, y: 3 * sy, width: 8 * sx, height: 8 * sy))
        p.move(to: CGPoint(x: 22 * sx, y: 21 * sy))
        p.addLine(to: CGPoint(x: 22 * sx, y: 19 * sy))
        p.addCurve(to: CGPoint(x: 19 * sx, y: 15.13 * sy), control1: CGPoint(x: 22 * sx, y: 17.13 * sy), control2: CGPoint(x: 20.73 * sx, y: 15.57 * sy))
        p.move(to: CGPoint(x: 16 * sx, y: 3.13 * sy))
        p.addCurve(to: CGPoint(x: 16 * sx, y: 10.87 * sy), control1: CGPoint(x: 18.2 * sx, y: 3.9 * sy), control2: CGPoint(x: 18.2 * sx, y: 10.1 * sy))
        return p
    }
}
