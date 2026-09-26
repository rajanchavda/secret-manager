import Foundation
import LocalAuthentication

public enum AuthError: LocalizedError {
    case biometricsNotAvailable(String)
    case authenticationFailed(String)
    case userCancelled
    case sessionExpired
    
    public var errorDescription: String? {
        switch self {
        case .biometricsNotAvailable(let msg):
            return "Touch ID / Authentication unavailable: \(msg)"
        case .authenticationFailed(let msg):
            return "Authentication failed: \(msg)"
        case .userCancelled:
            return "Authentication cancelled by user."
        case .sessionExpired:
            return "Session has expired. Authentication required."
        }
    }
}

public final class BiometricAuth {
    public static let shared = BiometricAuth()
    
    private init() {}
    
    /// Requests Touch ID or Mac password authentication with a custom localized reason.
    public func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"
        
        var authError: NSError?
        
        // Prefer .deviceOwnerAuthentication which presents Touch ID first while providing
        // a "Use Password..." option so the user can enter their Mac password manually.
        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            policy = .deviceOwnerAuthentication
        } else if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else {
            let errorMsg = authError?.localizedDescription ?? "No authentication policy available"
            throw AuthError.biometricsNotAvailable(errorMsg)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else if let error = error as? LAError {
                    if error.code == .userCancel || error.code == .appCancel {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else if error.code == .userFallback {
                        // User explicitly clicked "Use Password" when biometrics policy required fallback
                        Task {
                            let fallbackContext = LAContext()
                            fallbackContext.localizedCancelTitle = "Cancel"
                            fallbackContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { fbSuccess, fbError in
                                if fbSuccess {
                                    continuation.resume()
                                } else if let fbError = fbError as? LAError, fbError.code == .userCancel || fbError.code == .appCancel {
                                    continuation.resume(throwing: AuthError.userCancelled)
                                } else {
                                    let desc = fbError?.localizedDescription ?? "Authentication failed"
                                    continuation.resume(throwing: AuthError.authenticationFailed(desc))
                                }
                            }
                        }
                    } else {
                        continuation.resume(throwing: AuthError.authenticationFailed(error.localizedDescription))
                    }
                } else {
                    let desc = error?.localizedDescription ?? "Unknown authentication failure"
                    continuation.resume(throwing: AuthError.authenticationFailed(desc))
                }
            }
        }
    }
}
