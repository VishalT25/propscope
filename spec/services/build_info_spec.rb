require "rails_helper"

RSpec.describe BuildInfo do
  it "reports the version from the VERSION file and the runtime" do
    info = described_class.call
    expect(info.version).to eq(Rails.root.join("VERSION").read.strip)
    expect(info.version).to match(/\A\d+\.\d+\.\d+\z/)
    expect([ info.ruby, info.rails, info.environment ]).to eq([ RUBY_VERSION, Rails.version, "test" ])
  end

  it "reads the git details from the environment when given (a Docker image has no .git)" do
    stub_const("ENV", ENV.to_h.merge("GIT_SHA" => "a" * 40, "GIT_BRANCH" => "main", "GIT_COMMITTED_AT" => "2026-11-10T12:00:00-05:00", "BUILD_TIME" => "2026-11-10T18:00:00Z"))
    info = described_class.call
    expect([ info.commit, info.short_commit, info.branch, info.dirty ]).to eq([ "a" * 40, "aaaaaaa", "main", false ])
    expect(info.committed_at).to eq(Time.utc(2026, 11, 10, 17))
    expect(info.built_at).to eq(Time.utc(2026, 11, 10, 18))
  end

  it "reads them from the checkout otherwise, and copes with there being no git at all" do
    stub_const("ENV", ENV.to_h.except("GIT_SHA", "GIT_BRANCH", "GIT_COMMITTED_AT", "BUILD_TIME"))
    expect(described_class.call.commit).to match(/\A\h{40}\z/) if Rails.root.join(".git").exist?

    allow_any_instance_of(Pathname).to receive(:exist?).and_return(false)
    info = described_class.call
    expect([ info.git?, info.commit, info.branch, info.committed_at, info.dirty ]).to eq([ false, nil, nil, nil, false ])
  end

  it "shows whether live data is on" do
    expect(described_class.call.live_data).to be(false)
    allow(LiveData).to receive(:enabled?).and_return(true)
    expect(described_class.call.live_data).to be(true)
  end
end
