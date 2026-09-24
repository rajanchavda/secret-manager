# `sec`: Touch ID Secret Vault for macOS

> **Shield your `.env` and secret files from AI agents & background tools.**  
> Keep secrets encrypted on disk with Touch ID, inject them directly into process memory during development, and lock/edit files via macOS Finder right-click.

---

## ⚡ The Threat Model

AI coding agents (Cursor, Claude Desktop, Antigravity, GitHub Copilot, local LLMs) inspect your project workspace, run shell tools (`cat`, `ripgrep`, `grep`), and ingest files into context windows.

If your `.env` contains live credentials (database connection strings, Stripe keys, OpenAI tokens), any agent tool call can read and log them.

**Why traditional approaches fail:**
If a utility decrypts `.env` to plaintext on disk while your dev server runs (`npm run dev`), the agent can read those secrets at any moment during development.

**How `sec` solves this:**
1. **Plaintext never touches the disk during development**: Real secrets are encrypted in `.env.vault` (AES-256-GCM with hardware-backed macOS Keychain key).
2. **Sanitized Placeholder**: The `.env` file on disk is replaced with masked dummy values (e.g. `API_KEY=locked_by_sec`) so project linters, syntax highlighters, and static tools never break.
3. **In-Memory Injection**: When you run `sec npm run dev`, Touch ID prompts once, decrypts secrets directly into RAM (`process.env`), and passes them to the child process. AI agents reading the filesystem only ever see dummy placeholders.
4. **Strict Zero-Cache (Single-Use)**: Every command execution requires a physical Touch ID tap. Decrypted secrets live exclusively in the child process memory and are destroyed when the command exits. No session tokens linger on disk for AI agents to piggyback on.
5. **Finder Right-Click Quick Actions**: Right-click any secret file in Finder to lock or edit it with Touch ID.

---

## 🚀 Installation

### One-line Installation
From this repository directory, run:
```bash
./install.sh
```
Or with `make`:
```bash
make install
```

This will:
1. Compile the native Swift release binary (only ~340KB with zero external dependencies).
2. Install the binary to `/usr/local/bin/sec` (or `~/.local/bin/sec`).
3. Install macOS Quick Actions into `~/Library/Services` for Finder right-click support.

---

## 🖱️ Finder Right-Click Usage

Once installed:
- **Lock a file**: Right-click `.env` (or any secret file) in macOS Finder ➡️ **Quick Actions** ➡️ **Lock Secrets with Touch ID (sec)**.
- **Edit a vault**: Right-click `.env.vault` in Finder ➡️ **Quick Actions** ➡️ **Edit Secrets with Touch ID (sec)**.

A native macOS notification banner will confirm when your file is protected.

---

## 💻 CLI Usage

### 1. Lock a Secret File
```bash
sec lock .env
```
* Encrypts `.env` into `.env.vault`.
* Generates a dummy `.env` on disk:
  ```env
  # 🔒 PROTECTED BY sec (Touch ID Secret Vault)
  # Real secrets are encrypted in .env.vault
  # Run commands: sec npm run dev   |   Edit secrets: sec edit
  
  DATABASE_URL=locked_by_sec
  STRIPE_SECRET_KEY=locked_by_sec
  PORT=3000
  ```
* Automatically adds `.env.vault` to `.gitignore`.

---

### 2. Run Commands with Secrets Injected (In-Memory)
Simply prefix any command with `sec`:
```bash
sec npm run dev
sec pnpm dev
sec cargo run
sec python app.py
sec docker compose up
```
* Prompts Touch ID once.
* Real secrets are injected into process memory (`process.env`).
* Output and interactive terminal TTY features (colors, curses, Ctrl+C signals) work seamlessly.
* Monorepo friendly: automatically searches parent directories if running inside a nested subpackage!

---

### 3. Safely Edit Secrets
```bash
sec edit .env
```
* Prompts Touch ID.
* Decrypts secrets into an ephemeral, secure temporary buffer (`0600` permissions).
* Opens your `$EDITOR` (VS Code `--wait`, Cursor `--wait`, Nano, or Vim).
* On save and close: automatically re-encrypts `.env.vault`, refreshes the placeholder `.env`, and securely shreds the temporary file.

---

### 4. View Secrets in Terminal
```bash
sec view .env
```
* Prompts Touch ID and outputs decrypted key-value pairs to terminal stdout.

---

### 5. Check Vault & Session Status
```bash
sec status
```
Outputs:
```text
=== sec Status ===
🔑 Keychain Master Key: ✅ Configured (Secure Enclave / Keychain)
🛡️  Access Policy:       🔒 Strict Zero-Cache (Single-Use)
                       (Every command requires Touch ID; no lingering cache for AI agents)
📁 Current Vault:       Found '.env.vault' at /Users/you/project
```

Inspect access policy:
```bash
sec session
```

---

### 6. Permanently Unlock (Restore Plaintext to Disk)
```bash
sec unlock .env
```
* Prompts Touch ID, restores plaintext `.env` on disk, and removes `.env.vault`.

---

## 🏗️ Architecture & Security

- **Cryptography**: AES-256-GCM via Apple's native `CryptoKit`.
- **Key Storage**: 256-bit symmetric key stored in macOS Keychain (`kSecClassGenericPassword`), protected by macOS hardware security.
- **Biometrics**: Apple `LocalAuthentication` (`LAPolicy.deviceOwnerAuthenticationWithBiometrics`) with automatic fallback to Mac login password if the MacBook lid is closed or docked.
- **Zero Third-Party Dependencies**: Pure native Swift utilizing Apple system frameworks (`CryptoKit`, `Security`, `LocalAuthentication`, `Foundation`).
- **Memory Safety**: No plaintext ever written to disk during `sec run`. Temporary edit buffers are shredded with random bytes before deletion.

---

## 🧪 Running Tests

```bash
make test
```
Runs the XCTest suite validating encryption round-trips, `.env` parsing, and vault URL resolution.

---

## 📄 License
MIT License.
