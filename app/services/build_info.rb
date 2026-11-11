require "open3"

# What is running: the version (VERSION file), the git commit and branch it was built from, and the runtime. Git details come
# from GIT_SHA / GIT_BRANCH / GIT_COMMITTED_AT / BUILD_TIME when set (a Docker image has no .git), otherwise from the checkout.
class BuildInfo
  VERSION = Rails.root.join("VERSION").read.strip.freeze

  Info = Data.define(:version, :commit, :branch, :committed_at, :dirty, :built_at, :ruby, :rails, :environment, :live_data) do
    def short_commit = commit&.first(7)
    def git? = commit.present?
  end

  def self.call = new.call

  def call
    Info.new(version: VERSION, commit: env("GIT_SHA") || git("rev-parse", "HEAD"), branch: env("GIT_BRANCH") || git("rev-parse", "--abbrev-ref", "HEAD"),
             committed_at: committed_at, dirty: env("GIT_SHA") ? false : git("status", "--porcelain", "--untracked-files=no").present?,
             built_at: parse_time(env("BUILD_TIME")), ruby: RUBY_VERSION, rails: Rails.version, environment: Rails.env, live_data: LiveData.enabled?)
  end

  private

  def env(key) = ENV[key].presence

  def committed_at = parse_time(env("GIT_COMMITTED_AT") || git("log", "-1", "--format=%cI"))

  def parse_time(value) = value && Time.zone.parse(value)

  # Read-only git calls with fixed arguments (no shell). Nil when there is no checkout or git is missing.
  def git(*args)
    return nil unless Rails.root.join(".git").exist?

    out, status = Open3.capture2("git", "-C", Rails.root.to_s, *args, err: File::NULL)
    status.success? ? out.strip : nil
  rescue SystemCallError
    nil
  end
end
