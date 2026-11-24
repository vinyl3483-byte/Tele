import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?

    func signInWithApple() async throws -> String {
        if let pending = continuation {
            continuation = nil
            pending.resume(throwing: TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 401)))
        }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWin = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWin
        }
        if let anyWin = scenes.flatMap({ $0.windows }).first {
            return anyWin
        }
        return ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let cont = continuation
        continuation = nil
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let jwt = String(data: tokenData, encoding: .utf8) else {
            cont?.resume(throwing: TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 401)))
            return
        }
        cont?.resume(returning: jwt)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cont = continuation
        continuation = nil
        cont?.resume(throwing: TelefamAPIError.sanitized(TelefamCoreBridge.sanitizeError(httpStatus: 401)))
    }
}
