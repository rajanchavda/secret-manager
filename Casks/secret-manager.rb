cask "secret-manager" do
  version "1.0.0"
  sha256 :no_check # Automatically updated on release

  url "https://github.com/rajanchavda/security-manager/releases/download/v#{version}/Secret-Manager-#{version}.dmg"
  name "Secret Manager"
  desc "Hardware-grade Touch ID Secret Manager and stealth secret injection"
  homepage "https://github.com/rajanchavda/security-manager"

  app "Secret Manager.app"
  binary "#{appdir}/Secret Manager.app/Contents/MacOS/sec", target: "sec"

  postflight do
    system_command "xattr",
                   args: ["-cr", "#{appdir}/Secret Manager.app"]
  end

  livecheck do
    url :url
    strategy :github_latest
  end
end

