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
        
        var authError: NSError?
        
        // Prefer biometrics, but fallback to device owner password if biometrics aren't configured or lid is closed
        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            policy = .deviceOwnerAuthentication
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
