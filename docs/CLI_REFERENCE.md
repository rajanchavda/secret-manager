# `sec` CLI Command Reference

`sec` is an Apple Silicon Touch ID Secret Vault for macOS. It shields sensitive `.env` and credential files from AI coding agents (such as Cursor, Claude Desktop, Antigravity, GitHub Copilot, and local LLMs) by keeping real secrets hardware-encrypted in the Apple Secure Enclave and injecting them directly into child process RAM on Touch ID biometric authentication.

---

## Command Quick Index

| Command | Category | Description |
|---|---|---|
| [`sec <cmd...>`](#1-sec-command--sec-run) | Core | Run any dev server/script with secrets injected into RAM |
| [`sec lock`](#2-sec-lock) | Core | Encrypt secrets with Touch ID and create decoy placeholder on disk |
| [`sec edit`](#3-sec-edit) | Core | Safely edit secrets in an ephemeral buffer with auto-re-encryption |
| [`sec view`](#4-sec-view) | Core | Decrypt and print secrets to stdout (formats JSON automatically) |
| [`sec unlock`](#5-sec-unlock) | Core | Decrypt vault back to plaintext on disk and archive old vault in trash |
| [`sec status`](#6-sec-status) | Discovery | Show master key status, zero-cache mode, and nearest project vault |
| [`sec list`](#7-sec-list) | Discovery | Audit all protected vaults across your Mac grouped by directory |
| [`sec scan`](#8-sec-scan) | Discovery | Discover and register unindexed `.vault` files across folders |
| [`sec backup`](#9-sec-backup) | Backup | Create versioned snapshot backups of encrypted vaults |
| [`sec restore`](#10-sec-restore) | Backup | Roll back an active vault to an earlier version snapshot |
| [`sec trash`](#11-sec-trash) | Backup | Recover or purge soft-deleted and unlocked vaults |
| [`sec export-key`](#12-sec-export-key) | Security | Export master recovery key for backups or Mac migration |
| [`sec import-key`](#13-sec-import-key) | Security | Import master recovery key onto a new or wiped Mac |
| [`sec session`](#14-sec-session) | Security | Inspect access policy state or clear session cache |
| [`sec logout`](#15-sec-logout) | Security | Instantly lock session; requires Touch ID on next command |
| [`sec install-finder`](#16-sec-install-finder) | System | Install macOS Finder right-click Quick Action services |

---

## 1. Core Operations

### 1. `sec <command...>` / `sec run`
Run any child process with real secrets decrypted and injected directly into RAM (`process.env`). Plaintext never touches your storage drive, and secrets self-destruct as soon as the process terminates.

```bash
# Shorthand usage (any unknown subcommand is forwarded to run)
sec npm run dev
sec cargo run
sec python app.py
sec docker compose up

# Explicit run command
sec run npm start

# Inject a specific custom vault/secret file
sec -f .env.local npm run dev
sec --file credentials.json python main.py
sec --vault backend.vault go run main.go
```

#### Options:
- `-f, --file, --vault <file>`: Target a specific `.env`, JSON, or `.vault` file instead of the default `.env`.

---

### 2. `sec lock`
Encrypts a sensitive plaintext file into an AES-256-GCM `.vault` file backed by the Apple Silicon Secure Enclave. Automatically replaces the disk file with a masked decoy placeholder (`KEY=locked_by_sec`) so that IDE linters and parsers continue to function while AI agents cannot read real secrets.

```bash
# Locks default .env in current folder
sec lock

# Locks a specific file
sec lock .env.local
sec lock credentials.json

# Force re-locking even if file is already shielded
sec lock --force .env
```

#### Options:
- `--force, -f`: Bypass already-locked checks and force re-encryption with the current file contents.

---

### 3. `sec edit`
Safely decrypts the vault into a secure, ephemeral in-memory temporary file with strict `0600` POSIX permissions, and opens it in your default `$EDITOR` (VS Code `--wait`, Cursor `--wait`, Nano, or Vim). Upon closing, the file is automatically re-encrypted, the disk decoy is refreshed, and the buffer is securely wiped.

```bash
# Edit default .env.vault
sec edit

# Edit a specific file's vault
sec edit .env.staging
sec edit config.json
```

---

### 4. `sec view` (alias: `sec show`)
Prompts for Touch ID biometric verification and prints decrypted secrets directly to the terminal standard output. If the file is JSON, it formats and color-indents the output automatically.

```bash
# View .env secrets
sec view .env

# View JSON secrets with automatic pretty-printing
sec view config.json
sec show credentials.json
```

---

### 5. `sec unlock`
Permanently decrypts the vault, restores the original plaintext file back to disk, and moves the old encrypted vault into soft-deleted trash to prevent accidental data loss.

```bash
# Interactive prompt (requires confirmation)
sec unlock .env

# Skip confirmation prompt
sec unlock --yes .env
sec unlock -f .env
```

#### Options:
- `--yes, -y, --force, -f`: Skip interactive confirmation prompt (`y/N`).

---

## 2. Discovery & Inspection

### 6. `sec status`
Displays the health and state of your local `sec` environment, including Apple Silicon hardware key status, Zero-Cache single-use policy status, the nearest detected project vault, and the total count of registered vaults.

```bash
sec status
```

#### Example Output:
```text
=== sec Status ===
🔑 Hardware Master Key: ✅ Configured (Apple Silicon Secure Enclave)
🛡️  Access Policy:       🔒 Strict Zero-Cache (Single-Use)
                       (Every command requires Touch ID; no lingering cache for AI agents)
📁 Current Vault:       Found '.env.vault' at /Users/you/Developer/project
📋 Global Vaults:       3 registered across Mac (run 'sec list' to view)
```

---

### 7. `sec list` (alias: `sec ls`)
Lists all registered vaults across your Mac grouped by directory. Displays plain target name, vault file size, active status (e.g. `Decoy active on disk`), and last modified timestamp.

```bash
# Standard table view
sec list

# Scan user home directory for unindexed vaults
sec list --scan

# Scan a specific directory tree
sec list --scan ~/Developer

# Prune missing or moved vaults from the registry
sec list --prune

# Output machine-readable JSON (ideal for CI/CD or scripting)
sec list --json
```

#### Options:
- `--scan, -s [directory]`: Recursively discover and register vaults in the given directory (defaults to user home `~`).
- `--prune, -p`: Remove missing or deleted vault paths from the global registry.
- `--json`: Output full registry status as structured JSON.

---

### 8. `sec scan`
Shorthand for discovering and indexing existing `.vault` files across a folder tree without manually navigating into each repository.

```bash
sec scan
sec scan ~/Developer
sec scan ~/Projects
```

---

## 3. Backups, Versioning & Trash

### 9. `sec backup`
Creates an immutable, versioned snapshot of your encrypted vault in `~/.sec/backups/`. Allows you to safely make secret changes knowing you can roll back at any point.

```bash
# Create a snapshot for the current project vault
sec backup .env

# Create snapshots for all registered vaults across your Mac
sec backup --all

# List all available snapshots with version numbers and key counts
sec backup --list
```

#### Options:
- `--all`: Trigger backups for all vaults recorded in the global registry.
- `--list`: Print a table of all existing snapshots, version IDs, key counts, and timestamps.

---

### 10. `sec restore`
Rolls back a project vault to a previous version snapshot. Restores both the active encrypted vault and the on-disk decoy placeholder.

```bash
# Roll back to the most recent snapshot in current project
sec restore .env

# Restore a specific version number
sec restore .env -v 2
sec restore .env --version 1

# Restore using snapshot UUID prefix
sec restore --version 8f2a1b4c
```

#### Options:
- `-v, --version <version|id>`: Specify target version number (`v2`) or snapshot ID prefix.

---

### 11. `sec trash`
Inspects and manages soft-deleted vaults. When vaults are unlocked or removed, `sec` automatically archives them in the trash bin to prevent accidental permanent data loss.

```bash
# List all trashed vaults
sec trash

# Restore a trashed vault by ID prefix
sec trash --restore 8f2a1b4c

# Permanently delete a single trashed vault
sec trash --purge 8f2a1b4c

# Empty the entire trash bin
sec trash --empty
```

#### Options:
- `--restore, -r <id>`: Recover a trashed vault back to its project directory.
- `--purge, -p <id>`: Permanently delete a specific vault from trash.
- `--empty, --purge-all`: Empty all soft-deleted vaults permanently.

---

## 4. Key Management & System

### 12. `sec export-key` (alias: `sec backup-key`)
Exports the base64-encoded master recovery key from the macOS Keychain. Keep this key stored in a password manager (e.g. 1Password, Bitwarden) for disaster recovery or when migrating to a new Mac.

```bash
sec export-key
```

---

### 13. `sec import-key` (alias: `sec restore-key`)
Imports a master recovery key onto a new or wiped Mac, allowing all your existing `.vault` files to be decrypted immediately with Touch ID on the new hardware.

```bash
# Pass key as an argument
sec import-key "BASE64_KEY_STRING..."

# Or enter interactively
sec import-key
```

---

### 14. `sec session`
Inspects or clears the biometric session cache. In strict Zero-Cache mode (the default), every command requires a fresh Touch ID tap to prevent background AI processes from hijacking credentials.

```bash
# Inspect session policy and status
sec session status

# Purge any cached session credentials
sec session clear
```

---

### 15. `sec logout`
Shorthand to immediately clear any cached biometric session credentials, enforcing a physical Touch ID prompt on the very next operation.

```bash
sec logout
```

---

### 16. `sec install-finder`
Installs macOS Finder Quick Actions into `~/Library/Services/`. Once installed, you can right-click any `.env` or `.vault` file directly in Finder to lock, unlock, view, or edit secrets with native macOS notification confirmations.

```bash
sec install-finder
```

---

## Environment & Exit Codes

### Exit Codes
- `0`: Operation succeeded or child process exited cleanly.
- `1`: Operation error (file not found, biometric cancelled, or invalid arguments).
- `Exit code of child process`: When running `sec <command...>`, the exit code returned by your dev server or script is forwarded directly.

### Global Options
- `--help, -h, help`: Print the CLI command overview.
- `--version, -v, version`: Print the installed version number (`sec version 1.0.0`).
