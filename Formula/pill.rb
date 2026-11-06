# updater: marcellovictorino/pill
class Pill < Formula
  desc "Run the Pi coding agent with local models served by llama.cpp"
  homepage "https://github.com/marcellovictorino/pill"
  # Release v0.5.0 is not tagged yet. Until it is, sha256 and COMMIT below are
  # placeholders (all zeros). The tap's updater fills both in once the tag exists.
  url "https://github.com/marcellovictorino/pill/archive/refs/tags/v0.5.0.tar.gz"
  sha256 "c8ae582a3a3ed45894bf013f245b595cff05becf2bf75b8715625e4f708e8a0e" # checksum: set by the updater
  license "MIT"
  head "https://github.com/marcellovictorino/pill.git", branch: "main"

  # The tag's commit. A source archive has no Git data, so it is stamped in.
  COMMIT = "4edbdc4abd4d8d2c5b02f082dadfb8b1a066bd98".freeze # commit: set by the updater

  depends_on "go" => :build
  depends_on "llama.cpp"
  depends_on "pi-coding-agent"

  def install
    ldflags = "-X github.com/marcellovictorino/pill/internal/version.buildCommit=#{COMMIT}"
    system "go", "build", *std_go_args(ldflags:)
  end

  test do
    output = shell_output("#{bin}/pill version")
    assert_match "version: #{version}", output
    assert_match "commit: #{COMMIT[0, 7]}", output
  end
end
