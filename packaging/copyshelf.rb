cask "copyshelf" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/ethanclawsie/copyshelf-mac/releases/download/v#{version}/CopyShelf-#{version}.zip"
  name "CopyShelf"
  desc "Menu bar shelf of reusable text snippets — click to copy"
  homepage "https://github.com/ethanclawsie/copyshelf-mac"

  depends_on macos: ">= :sonoma"

  app "CopyShelf.app"

  # The app is ad-hoc signed (not notarized), so clear the download quarantine flag
  # to let it open without a Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/CopyShelf.app"]
  end

  uninstall quit: "com.ethanclawsie.copyshelf"

  zap trash: [
    "~/Library/Application Support/CopyShelf",
    "~/Library/Preferences/com.ethanclawsie.copyshelf.plist",
  ]
end
