# `sec` — Architecture, App Context & Developer Guidelines

> **Touch ID Secret Vault for macOS**  
> Hardware-encrypted credentials in Apple Silicon Secure Enclave, decoy generation for `.env`, direct in-memory RAM injection for development child processes, and real-time AI Agent Radar monitoring.

---

## 1. System Overview & The Threat Model

Modern AI coding agents (such as Claude Code, Cursor, Windsurf, GitHub Copilot, Antigravity, and local LLMs) routinely inspect workspace directories, run discovery shell commands (`cat`, `grep`, `ripgrep`, `find`), and ingest file contents directly into model context windows.

When `.env` files contain active API tokens (OpenAI, Anthropic, Stripe, AWS, database URLs), agents inevitably read them and serialize them into prompt logs, third-party server transcripts, or persistent conversation histories.

### The Failure of Traditional Solutions
- Decrypting secrets to plaintext `.env` on disk while running a dev server (`npm run dev`) creates an open attack window: any tool or background agent can read the plaintext while the developer is working.
- `.gitignore` prevents git commits, but offers zero protection against local tools and AI agents operating inside the local workspace.

### How `sec` Eliminates the Threat
1. **Zero Plaintext on Disk**: Real secrets are encrypted in `.env.vault` using **AES-256-GCM** with a hardware master key secured inside the **Apple Silicon Secure Enclave**.
2. **Harmless Decoy File**: The disk `.env` file contains safe masked placeholders (e.g., `DATABASE_URL=locked_by_sec`, `STRIPE_KEY=locked_by_sec`). Linters, syntax highlighters, Prisma generators, and TypeScript compilers continue to function without crashing.
3. **Pure In-Memory Injection**: When running `sec npm run dev` (or via Secret Manager Runner Studio), Touch ID prompts the developer once. Secrets are decrypted strictly into RAM (`process.env`) and passed to the child process. Plaintext is never written to disk.
4. **Stealth Preload Loaders (Defeating `ps -E`)**: For Node.js and Python development, `sec` uses ephemeral self-destructing preload hooks rather than passing secrets through `execve` `envp`. AI agents running `ps -E` or inspecting Darwin's `KERN_PROCARGS2` cannot see plaintext secrets.
5. **Strict Zero-Cache (Single-Use)**: By default, every command requires a physical Touch ID tap. No decrypted session tokens linger on disk for background agents to exploit.
6. **AI Agent Radar**: Real-time macOS `FSEvents` monitoring intercepts and logs file access attempts by AI agents (Cursor, Claude, Copilot, terminals), proving that only decoy data was ingested while real keys stayed in the Secure Enclave.

---

## 2. Codebase Architecture

The project is structured as a Swift Package Manager (SPM) project with three primary targets and a web landing page:

```
cool-meitner/
├── Package.swift               # SPM definition (macOS 14 Sonoma+, Swift 5.9+)
├── Makefile                    # Standard build, release, test, and install targets
├── install.sh                  # One-line installer script
├── Sources/
│   ├── SecCore/                # Shared framework with crypto, auth, and system logic
│   │   ├── Core/
│   │   │   ├── BiometricAuth.swift       # Apple LocalAuthentication (Touch ID / Apple Watch)
│   │   │   ├── CryptoEngine.swift        # AES-256-GCM encryption & decryption via CryptoKit
│   │   │   ├── EditorEngine.swift        # Safe editing via $EDITOR with 0600 temp file & byte shredding
│   │   │   ├── EnvParser.swift           # Parsing, multiline, inline comments, decoy generation
│   │   │   ├── FileWatcher.swift         # macOS FSEvents file monitor powering AI Agent Radar
│   │   │   ├── GitIgnoreManager.swift    # Auto-adding *.vault to .gitignore
│   │   │   ├── KeychainManager.swift     # Secure Enclave P-256 hardware key agreement + HKDF
│   │   │   ├── MemoryMonitor.swift       # Process memory footprint & RAM monitoring
│   │   │   ├── ProcessRunner.swift       # Child process spawning, stealth preload, TTY pass-through
│   │   │   ├── RegistryManager.swift     # Global registry of vaults (~/.sec/vaults.json)
│   │   │   ├── SessionManager.swift      # Biometric grace periods & sleep lock
│   │   │   └── VaultEngine.swift         # High-level lock, unlock, view, and sync orchestrator
│   │   └── Integrations/
│   │       ├── FinderInstaller.swift     # macOS Automator Quick Actions installer
│   │       └── Notifier.swift            # Native macOS notification center alerts
│   ├── sec/                    # Native CLI binary (compiled to ~340KB)
│   │   ├── main.swift                    # CLI entry point
│   │   └── CLI/SecCLI.swift              # Argument parsing, command dispatch, formatting
│   └── SecApp/                 # Secret Manager macOS SwiftUI Desktop & Menubar Application
│       ├── SecApp.swift                  # Application delegate, NSWindow, NSStatusItem companion
│       ├── Store/SecAppStore.swift       # Unified @MainActor state store & Combine observers
│       ├── Models/
│       │   ├── AppFont.swift             # Dynamic font scaling and typography system (0.8x - 1.6x)
│       │   └── VaultModels.swift         # Data structures: RadarEvent, VaultItem, SecretEntry
│       ├── Views/
│       │   ├── MainWindowView.swift      # Standalone pro dashboard layout
│       │   ├── MainPopoverView.swift     # Compact menubar companion popover
│       │   ├── AgentRadarView.swift      # Live AI agent radar monitor widget
│       │   ├── AgentRadarFullView.swift  # Full-screen radar activity log & audit stream
│       │   ├── RunnerStudioView.swift    # Visual dev server runner with live stdout/stderr
│       │   ├── DeepScannerView.swift     # Recursive folder scanner for unshielded .env files
│       │   ├── VaultDetailView.swift     # Secret table, raw editor, and security score tabs
│       │   ├── SecretTableView.swift     # Key-value inspector with entropy and leak risk scores
│       │   ├── RawEnvEditorView.swift    # Visual in-memory text editor with dirty diffing
│       │   ├── SecurityAuditView.swift   # Overall security score and vulnerability breakdown
│       │   ├── GraceBarView.swift        # Biometric session timer & grace period selector
│       │   ├── DropZoneView.swift        # Drag & drop instant file shielding
│       │   └── MemoryFooterView.swift    # RAM monitor & Secure Enclave hardware verification
│       └── Resources/                    # App icons (icns, png)
├── Tests/secTests/             # Unit and integration test suite (XCTest)
└── web/                        # Public marketing, showcase & documentation website
    ├── index.html              # Modern responsive landing page
    ├── css/style.css           # Styling, design system, dark/light theme, typography
    ├── css/terminal.css        # Interactive terminal, radar, and GUI mockups
    ├── js/app.js               # Theme switcher, terminal simulator, interactive demos
    └── assets/icon.svg         # Gradient shield brand asset
```

---

## 3. Key Features & How They Work

### A. CLI Commands (`sec`)
- `sec lock <file>`: Encrypts file to `<file>.vault`, writes decoy placeholders to `<file>`, adds to `.gitignore`, registers in `~/.sec/vaults.json`. Idempotent: detects if already locked to prevent overwriting.
- `sec <command>` (or `sec run <cmd>`): Prompts Touch ID, decrypts secrets directly into memory, executes child process with stealth loaders.
- `sec edit <file>`: Prompts Touch ID, opens `$EDITOR` with 0600 temp buffer, overwrites buffer with random bytes before shredding upon save.
- `sec view <file>`: Prompts Touch ID, prints formatted secrets to terminal stdout without disk artifacts.
- `sec list`: Displays all registered vaults. Supports `--scan <path>` to discover unindexed vaults, `--prune` to remove missing entries, and `--json` for automated scripts.
- `sec status`: Reports Secure Enclave key health, active access policy, and current folder vault status.
- `sec session`: Displays or configures biometric grace period settings.
- `sec unlock <file>`: Prompts Touch ID, permanently restores plaintext on disk, deletes `<file>.vault`.
- `sec install-finder`: Installs native macOS Quick Actions into `~/Library/Services`.

### B. Secret Manager macOS Application
- **Menubar Companion & Standalone Window**: Resides in macOS status bar for instant access or opens as a full dashboard window.
- **AI Agent Radar**: Subscribes to `FSEvents` and process telemetry. When Cursor, Claude, Copilot, or terminal tools touch `.env` or `.env.vault`, Secret Manager records the event, displaying the agent name, timestamp, and verification that only decoy data was exposed.
- **Runner Studio**: Visual runner where developers select a vault, choose dev commands (e.g., `npm run dev`, `cargo run`), click **Run**, and watch live formatted logs while secrets are injected into RAM. Shows live PID and RAM usage.
- **Deep Discovery Scanner**: Recursively scans folders (e.g. `~`, `~/Developer`) to find unshielded `.env` and `.env.local` files, providing 1-click shielding.
- **Secret Inspector & Security Audit**: Evaluates key entropy, classifies sensitive tokens (Stripe `sk_live`, OpenAI `sk-`, AWS, Postgres credentials), calculates a 0–100 Security Score, and alerts on weak keys.
- **Biometric Grace Periods**: Configurable session durations (Immediate Single-Use, 15m, 30m, 1h, Until Sleep) with automatic invalidation upon Mac sleep or display lock.
- **Dynamic Typography**: Adjustable font scale (0.8x to 1.6x) for accessibility and dense layouts.

---

## 4. Development & Build Workflows

### Command Prefix Rule for Agents
> [!IMPORTANT]
> **Always prefix terminal and shell commands with `rtk`** (Rust Token Killer) when running commands in this environment (e.g. `rtk git status`, `rtk make build`). This minimizes token overhead and context noise.

### Common Build & Test Commands
```bash
# Build debug binary
rtk swift build

# Build release binaries (CLI and SecApp)
rtk make build

# Run test suite
rtk make test

# Install to system (/usr/local/bin or ~/.local/bin)
rtk make install

# Clean build artifacts
rtk make clean
```

---

## 5. Coding Conventions & Best Practices

1. **Zero External Dependencies**: All cryptography, biometrics, process management, and UI logic MUST rely exclusively on Apple system frameworks (`CryptoKit`, `LocalAuthentication`, `Security`, `Foundation`, `AppKit`, `SwiftUI`, `Combine`). Do not introduce third-party Swift packages or npm dependencies.
2. **Cryptographic Hardening**:
   - Master key MUST use hardware-backed Secure Enclave (`CryptoKit.SecureEnclave.P256.KeyAgreement` + HKDF). Never fall back to insecure plaintext storage.
   - Symmetric cipher MUST be AES-256-GCM (`CryptoKit.AES.GCM`).
   - Ephemeral buffers containing sensitive data MUST be wiped with random bytes (`memset_s` or secure overwrite) prior to deallocation.
3. **Decoy Integrity**:
   - Decoy files generated on disk must remain syntactically valid for common dotenv parsers, YAML/TOML parsers, or JSON formatters.
   - Placeholder value format: `locked_by_sec`.
   - Never overwrite a vault file if the target file is already masked.
4. **SwiftUI Architecture**:
   - UI state is managed centrally in `SecAppStore.swift` marked `@MainActor`.
   - Dynamic typography must respect `AppFont.scaled(...)` for consistent scaling across custom views.
   - Support both macOS Light and Dark appearances with high-contrast emerald/teal accents.
5. **Path & Subpackage Resolution**:
   - Monorepo traversal: when executing inside nested packages (e.g., `packages/backend/`), `sec` traverses parent directories to discover the root vault.
   - Always expand tilde (`~`) paths safely using `FileManager.default.homeDirectoryForCurrentUser`.
