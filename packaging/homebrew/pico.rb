cask "pico" do
  version "1.0.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/linjunc/pico/releases/download/v#{version}/Pico-v#{version}.dmg"
  name "Pico"
  desc "Keyboard-first local clipboard manager for macOS"
  homepage "https://github.com/linjunc/pico"

  depends_on macos: ">= :sonoma"

  app "Pico.app"

  zap trash: [
    "~/Library/Application Support/Pico",
    "~/Library/Preferences/com.linjunc.pico.plist",
    "~/Library/Caches/com.linjunc.pico"
  ]
end
