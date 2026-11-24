import SwiftUI
import AuthenticationServices

struct TelefamBrandLogoView: View {
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            Circle()
                .fill(TelefamColors.crimson)
                .frame(width: size, height: size)
            PaperPlaneShape()
                .fill(Color.white)
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(x: -size * 0.02, y: size * 0.01)
        }
    }
}

struct PaperPlaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24.0
        let sy = rect.height / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 21.4 * sx, y: 3.2 * sy))
        p.addLine(to: CGPoint(x: 18.4 * sx, y: 20.2 * sy))
        p.addLine(to: CGPoint(x: 12.1 * sx, y: 16.9 * sy))
        p.addLine(to: CGPoint(x: 9.5 * sx, y: 19.4 * sy))
        p.addLine(to: CGPoint(x: 8.9 * sx, y: 14.8 * sy))
        p.addLine(to: CGPoint(x: 18.6 * sx, y: 6.1 * sy))
        p.addLine(to: CGPoint(x: 6.6 * sx, y: 13.6 * sy))
        p.addLine(to: CGPoint(x: 2.3 * sx, y: 12.2 * sy))
        p.closeSubpath()
        return p
    }
}

struct TopRedWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.72))
        p.addCurve(
            to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.52),
            control1: CGPoint(x: rect.width * 0.80, y: rect.height * 1.05),
            control2: CGPoint(x: rect.width * 0.62, y: rect.height * 0.35)
        )
        p.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.75),
            control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.72),
            control2: CGPoint(x: rect.width * 0.12, y: rect.height * 0.88)
        )
        p.closeSubpath()
        return p
    }
}

struct BottomRedWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height * 0.22))
        p.addCurve(
            to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.40),
            control1: CGPoint(x: rect.width * 0.22, y: rect.height * 0.62),
            control2: CGPoint(x: rect.width * 0.36, y: rect.height * 0.20)
        )
        p.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.28),
            control1: CGPoint(x: rect.width * 0.74, y: rect.height * 0.65),
            control2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.12)
        )
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

struct AuthView: View {
    @ObservedObject var viewModel: TelefamViewModel
    @FocusState private var focusedOtpIndex: Int?

    private var isDark: Bool { viewModel.isDarkTheme }
    private let brandRed = TelefamColors.crimson

    var body: some View {
        ZStack {
            TelefamColors.background(isDark: isDark).ignoresSafeArea()

            VStack(spacing: 0) {
                TopRedWaveShape()
                    .fill(brandRed)
                    .frame(height: 78)
                    .ignoresSafeArea(edges: .top)
                Spacer()
                BottomRedWaveShape()
                    .fill(brandRed)
                    .frame(height: 104)
                    .ignoresSafeArea(edges: .bottom)
            }

            ScrollView {
                VStack(spacing: 14) {
                    Spacer(minLength: 24)

                    TelefamBrandLogoView(size: 68)

                    Text("Telefam")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(brandRed)

                    Text("Stay connected. Stay together.")
                        .font(.system(size: 13))
                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))

                    VStack(spacing: 16) {
                        if viewModel.authStep == .enterEmail {
                            enterEmailCard
                        } else {
                            enterOTPCard
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 26)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(TelefamColors.surface(isDark: isDark))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isDark ? TelefamColors.darkBorder : Color.clear, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(isDark ? 0.32 : 0.08), radius: 20, y: 8)
                    )
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                    Spacer(minLength: 36)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .telefamSwipeBack(enabled: viewModel.authStep == .enterOTP) {
            viewModel.changeEmail()
        }
    }

    private var enterEmailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 4) {
                Text("Enter Your Email")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(brandRed)
                Text("Enter your email to get OTP")
                    .font(.system(size: 13))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
            }
            .frame(maxWidth: .infinity)

            Text("Email")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))

            HStack(spacing: 10) {
                MailOutlineVectorIcon()
                    .stroke(brandRed, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
                TextField("Enter your email", text: $viewModel.email)
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: TelefamMetrics.authButtonHeight)
            .overlay(
                RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                    .stroke(TelefamColors.border(isDark: isDark), lineWidth: 1)
            )

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(brandRed)
            }

            Button {
                Task { await viewModel.sendOTP(isResend: false) }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send OTP")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: TelefamMetrics.authButtonHeight)
                .background(brandRed)
                .cornerRadius(TelefamMetrics.authButtonRadius)
            }
            .disabled(viewModel.isLoading)

            HStack {
                Rectangle().fill(TelefamColors.border(isDark: isDark)).frame(height: 1)
                Text("or")
                    .font(.system(size: 12))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                    .padding(.horizontal, 8)
                Rectangle().fill(TelefamColors.border(isDark: isDark)).frame(height: 1)
            }

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { _ in
                Task { await viewModel.signInWithApple() }
            }
            .signInWithAppleButtonStyle(isDark ? .white : .whiteOutline)
            .id(isDark)
            .frame(height: TelefamMetrics.authButtonHeight)
            .cornerRadius(TelefamMetrics.authButtonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                    .stroke(TelefamColors.border(isDark: isDark), lineWidth: isDark ? 0 : 1)
            )
        }
    }

    private var enterOTPCard: some View {
        VStack(spacing: 14) {
            Text("Enter OTP")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(brandRed)

            VStack(spacing: 2) {
                Text("We sent a verification code to")
                    .font(.system(size: 13))
                    .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                Text(viewModel.email)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
            }

            Text("Enter the 6-digit code or tap the verification link in your email.")
                .font(.system(size: 12))
                .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("•", text: Binding(
                        get: { viewModel.otpDigits.indices.contains(index) ? viewModel.otpDigits[index] : "" },
                        set: { newVal in
                            guard viewModel.otpDigits.indices.contains(index) else { return }
                            let filtered = newVal.filter { $0.isNumber }
                            if filtered.count > 1 {
                                let chars = Array(filtered.prefix(6))
                                for (i, ch) in chars.enumerated() where viewModel.otpDigits.indices.contains(i) {
                                    viewModel.otpDigits[i] = String(ch)
                                }
                                focusedOtpIndex = min(5, chars.count - 1)
                            } else {
                                viewModel.otpDigits[index] = String(filtered.prefix(1))
                                if !filtered.isEmpty && index < 5 {
                                    focusedOtpIndex = index + 1
                                }
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(TelefamColors.inkPrimary(isDark: isDark))
                    .focused($focusedOtpIndex, equals: index)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(TelefamColors.surface(isDark: isDark))
                    .cornerRadius(TelefamMetrics.authButtonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: TelefamMetrics.authButtonRadius)
                            .stroke(
                                focusedOtpIndex == index ? brandRed : TelefamColors.border(isDark: isDark),
                                lineWidth: focusedOtpIndex == index ? 1.6 : 1
                            )
                    )
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(brandRed)
            }

            Button {
                Task { await viewModel.verifyOTP() }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify OTP")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: TelefamMetrics.authButtonHeight)
                .background(brandRed)
                .cornerRadius(TelefamMetrics.authButtonRadius)
            }
            .disabled(viewModel.isLoading)

            VStack(spacing: 4) {
                let formatted = formatCooldown(viewModel.cooldownSeconds)
                if viewModel.cooldownSeconds > 0 {
                    HStack(spacing: 4) {
                        Text("Resend code in")
                            .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                        Text(formatted)
                            .foregroundColor(brandRed)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                    Text("After \(formatted) you can Resend code")
                        .font(.system(size: 12))
                        .foregroundColor(TelefamColors.inkSecondary(isDark: isDark))
                } else {
                    Button {
                        Task { await viewModel.sendOTP(isResend: true) }
                    } label: {
                        Text("Resend code")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(brandRed)
                            .frame(minHeight: TelefamMetrics.minTouchSize)
                    }
                }
            }

            Button {
                viewModel.changeEmail()
            } label: {
                Text("Change email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(brandRed)
                    .frame(minHeight: TelefamMetrics.minTouchSize)
            }
        }
    }

    private func formatCooldown(_ seconds: Int64) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
