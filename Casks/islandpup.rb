cask "islandpup" do
  version "0.1.0"
  sha256 "e45f4bd58bc33ae584f07a4e4cd215bc88b50ae655c8ae4f05d992c01c29553a"

  url "https://github.com/Pongchayanneung/islandpup/releases/download/v#{version}/IslandPup.zip"
  name "IslandPup"
  desc "Pixel border-collie mascot for the Mac Dynamic Island (unofficial Vorssaint fork)"
  homepage "https://github.com/Pongchayanneung/islandpup"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "IslandPup.app"

  # Ad-hoc signed and not notarized: drop the quarantine flag so the app opens normally.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/IslandPup.app"],
        writable_paths: ["IslandPup.app"],
        writable_base:  :appdir,
        must_succeed:   false
  end

  zap trash: "~/Library/Application Support/IslandPup"

  caveats <<~EOS
    IslandPup is ad-hoc signed and not notarized. If macOS still says it is blocked, run:
      xattr -dr com.apple.quarantine "#{appdir}/IslandPup.app"
  EOS
end
