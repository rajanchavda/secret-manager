# Agent Rules & Guidelines (`agents.md`)

> **Instructions and Guardrails for Autonomous AI Agents Working in this Repository**  
> Applies to Cursor, Claude Code, GitHub Copilot, Windsurf, Antigravity, and any automated AI tool or background process.

---

## 1. Prime Directives for AI Agents

1. **Respect Vault Integrity (`*.vault`)**:
   - Files ending in `.vault` (e.g. `.env.vault`, `secrets.json.vault`) are encrypted using **AES-256-GCM** with a hardware master key in the Apple Silicon Secure Enclave.
   - Do **NOT** attempt to inspect, decrypt, or tamper with `.vault` files using shell tools (`cat`, `hexdump`, `base64`). They require physical user Touch ID authentication.

2. **Respect Decoy Placeholders (`locked_by_sec`)**:
   - When inspecting `.env` files in this repository (or any project secured by `sec`), you will observe values like:
     ```env
     DATABASE_URL=locked_by_sec
     STRIPE_SECRET_KEY=locked_by_sec
     OPENAI_API_KEY=locked_by_sec
     ```
   - This is the intentional **Sanitized Placeholder Decoy**. Do **NOT** delete, erase, or replace these values with fake dummy keys, and do **NOT** ask the user to paste their real secrets into your prompt context.
   - Linters and type checkers will succeed because the environment keys are present and syntactically valid.

3. **Running Commands with In-Memory Secrets**:
   - When asked to run dev servers, test commands, or scripts that require environment variables, execute them with the `sec` CLI wrapper:
     ```bash
     sec npm run dev
     sec cargo run
     sec python app.py
     ```
   - The user will be prompted for Touch ID on their Mac, and the credentials will be injected directly into child process RAM without touching the hard drive.

4. **RTK Token Optimization**:
   - You MUST prefix all shell/terminal commands with `rtk` (Rust Token Killer) to avoid unnecessary context noise:
     ```bash
     rtk git status
     rtk git diff
     rtk make test
     rtk swift build
     ```

---

## 2. Technical Guardrails & Constraints

### Zero External Dependencies Rule
- The entire project is written in native Swift 5.9+ targeting macOS 14 (Sonoma) and later.
- **Never add external third-party SPM packages, CocoaPods, or npm libraries** to `Package.swift` or `Sources/`. All functionality must utilize Apple standard system libraries:
  - Cryptography: `CryptoKit`
  - Biometrics: `LocalAuthentication`
  - Key storage: `Security` / `CryptoKit.SecureEnclave`
  - GUI: `SwiftUI`, `AppKit`, `Combine`
  - Filesystem monitoring: `CoreServices` / `FSEvents`

### Memory Safety & Secret Hygiene
- If you touch `EditorEngine.swift` or any secret handling buffers:
  - Any raw sensitive data decrypted into temporary RAM buffers must be securely overwritten with random bytes or zeroed using `memset_s` before memory release or deletion.
  - Temporary files created during `sec edit` must use `0600` POSIX file permissions and be unlinked immediately after re-encryption.

### Idempotency & Safety Guards
- Any code dealing with `sec lock` or `sec unlock` must verify whether the target file is already masked before taking action.
- Never write `locked_by_sec` back into `.env.vault`.

---

## 3. Key Components Reference

| Component | Path | Purpose |
|---|---|---|
| **CryptoEngine** | `Sources/SecCore/Core/CryptoEngine.swift` | AES-256-GCM encryption & decryption with CryptoKit |
| **KeychainManager** | `Sources/SecCore/Core/KeychainManager.swift` | Hardware Secure Enclave key generation (P-256 + HKDF) |
| **BiometricAuth** | `Sources/SecCore/Core/BiometricAuth.swift` | LocalAuthentication Touch ID prompt & clamshell fallback |
| **ProcessRunner** | `Sources/SecCore/Core/ProcessRunner.swift` | In-memory RAM secret injection & stealth preload loaders |
| **FileWatcher** | `Sources/SecCore/Core/FileWatcher.swift` | FSEvents monitor powering live AI Agent Radar |
| **SecAppStore** | `Sources/SecApp/Store/SecAppStore.swift` | Unified @MainActor state store for the macOS GUI application |
| **MainWindowView** | `Sources/SecApp/Views/MainWindowView.swift` | Standalone sec Pro desktop window layout |
| **AgentRadarView** | `Sources/SecApp/Views/AgentRadarView.swift` | Real-time AI agent interception & protection feed |
| **RunnerStudioView**| `Sources/SecApp/Views/RunnerStudioView.swift` | Visual dev server execution studio with live logs |
| **DeepScannerView** | `Sources/SecApp/Views/DeepScannerView.swift` | System-wide search for unshielded `.env` files |

---

## 4. Workflows for Contributing Agents

When making changes to this codebase:
1. **Always read the corresponding view or core file before editing.**
2. **Preserve dynamic font scaling**: Use `AppFont.scaled(...)` whenever introducing custom typography in `SecApp/Views/`.
3. **Preserve Light & Dark mode support**: Ensure UI contrast is clean in both macOS appearance modes.
4. **Run tests before completing tasks**: Execute `rtk make test` or `rtk swift test`.
