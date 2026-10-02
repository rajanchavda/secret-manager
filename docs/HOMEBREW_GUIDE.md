# Homebrew Distribution Guide for Secret Manager

This guide explains how to distribute **Secret Manager** (`Secret Manager.app` + `sec` CLI) via Homebrew without requiring an Apple Developer Account.

---

## 1. Why Homebrew?

- **Zero Apple ID / Sign Key Needed**: When users install apps via `brew install --cask`, Homebrew installs the application directly into `/Applications` and manages Gatekeeper quarantine attributes automatically.
- **Single Command Installation**: Installs both the GUI desktop app and symlinks the `sec` CLI into `/opt/homebrew/bin/sec` or `/usr/local/bin/sec`.
- **Seamless Updates**: Users can update at any time with `brew upgrade secret-manager`.

---

## 2. Setting Up Your Homebrew Tap Repository (1-Minute Setup)

Homebrew allows anyone to maintain their own repository of packages ("tap").

### Step 1: Create the Tap Repository on GitHub
1. Go to GitHub and click **New Repository**.
2. Name it **`homebrew-tap`** (or **`tap`**).
   - Repository URL will be: `https://github.com/rajanchavda/homebrew-tap`
3. Set visibility to **Public**.
4. Check **Add a README file** and create the repo.

### Step 2: Add the Cask Formula
In your new `homebrew-tap` repository:
1. Create a folder named `Casks/`.
2. Add a file named `secret-manager.rb` (you can copy it directly from `Casks/secret-manager.rb` in this repo):

```ruby
cask "secret-manager" do
  version "1.0.0"
  sha256 "PASTE_SHA256_FROM_GITHUB_RELEASE"

  url "https://github.com/rajanchavda/file-sec/releases/download/v#{version}/Secret-Manager-#{version}.dmg"
  name "Secret Manager"
  desc "Hardware-grade Touch ID Secret Manager and stealth secret injection"
  homepage "https://github.com/rajanchavda/file-sec"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Secret Manager.app"
  binary "#{appdir}/Secret Manager.app/Contents/MacOS/sec", target: "sec"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Secret Manager.app"],
                   sudo: false
  end

  zap trash: [
    "~/.sec",
    "~/Library/Application Support/Secret Manager",
    "~/Library/Preferences/com.sec.SecretManager.plist",
  ]
end
```

3. Commit the file.

---

## 3. How Users Install & Upgrade

Once your `homebrew-tap` repo is created, users can install Secret Manager with:

```bash
# Add your tap
brew tap rajanchavda/tap

# Install Secret Manager (.app in /Applications and sec in PATH)
brew install --cask secret-manager
```

To update when a new version is released:
```bash
brew upgrade secret-manager
```

---

## 4. How Releases Work Automatically

Whenever you cut a new version in `file-sec`:

```bash
git tag v1.0.1
git push origin v1.0.1
```

1. GitHub Actions automatically builds the Universal 2 DMG: `Secret-Manager-1.0.1.dmg`.
2. GitHub Actions calculates the SHA256 checksum and uploads the DMG to the release.
3. In the GitHub Actions run summary, you will see the exact updated Cask snippet with the new `sha256`.
4. Update the `sha256` and `version` in your `homebrew-tap/Casks/secret-manager.rb`.
