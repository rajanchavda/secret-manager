cask "secret-manager" do
  version "1.0.0"
  sha256 :no_check # Updated automatically upon GitHub release

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
