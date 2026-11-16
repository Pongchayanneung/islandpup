cask "islandpup" do
  version "0.1.0"
  sha256 "e45f4bd58bc33ae584f07a4e4cd215bc88b50ae655c8ae4f05d992c01c29553a"

  url "https://github.com/Pongchayanneung/islandpup/releases/download/v#{version}/IslandPup.zip"
  name "IslandPup"
  desc "Pixel border-collie mascot for the Mac Dynamic Island (unofficial Vorssaint fork)"
  homepage "https://github.com/Pongchayanneung/islandpup"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "IslandPup.app"

  # The app is ad-hoc signed and not notarized, so drop the quarantine flag after install.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/IslandPup.app"],
                   must_succeed: false
  end

  zap trash: "~/Library/Application Support/IslandPup"
end
