require "rails_helper"

RSpec.describe BudgetGuard do
  let(:provider) { "sports_game_odds" } # 2,500 / month, 80% ceiling
  let(:now) { Time.utc(2026, 11, 9, 12) }

  it "counts spend against the monthly period and yields" do
    result = described_class.spend!(provider, 10, now: now) { :called }
    expect(result).to eq(:called)
    usage = ApiUsage.find_by(provider: provider, period: "2026-11")
    expect([ usage.units_used, usage.units_limit ]).to eq([ 10, 2500 ])
  end

  it "keeps separate counters per month" do
    described_class.spend!(provider, 5, now: now) { }
    described_class.spend!(provider, 7, now: now + 30.days) { }
    expect(ApiUsage.pluck(:period, :units_used).sort).to eq([ [ "2026-11", 5 ], [ "2026-12", 7 ] ])
  end

  it "refuses (without calling) when a request would pass 100%" do
    described_class.usage_for(provider, now).update!(units_used: 2495)
    called = false
    expect { described_class.spend!(provider, 6, now: now) { called = true } }.to raise_error(BudgetGuard::BudgetExceeded)
    expect(called).to be(false)
    expect(ApiUsage.find_by(provider: provider).units_used).to eq(2495)
  end

  it "allows spending exactly up to the limit" do
    described_class.usage_for(provider, now).update!(units_used: 2490)
    expect { described_class.spend!(provider, 10, now: now) { } }.not_to raise_error
  end

  it "reports optional snapshots allowed below 80% and dropped at 80%" do
    expect(described_class.optional_allowed?(provider, now: now)).to be(true)
    described_class.usage_for(provider, now).update!(units_used: 1999)
    expect(described_class.optional_allowed?(provider, now: now)).to be(true)
    described_class.usage_for(provider, now).update!(units_used: 2000)
    expect(described_class.optional_allowed?(provider, now: now)).to be(false)
  end

  it "instruments and logs when crossing 80%" do
    described_class.usage_for(provider, now).update!(units_used: 1995)
    events = []
    sub = ActiveSupport::Notifications.subscribe("budget_warning.propscope") { |*, payload| events << payload }
    described_class.spend!(provider, 10, now: now) { }
    ActiveSupport::Notifications.unsubscribe(sub)
    expect(events.size).to eq(1)
    expect(events.first[:provider]).to eq(provider)
  end

  it "records usage but never blocks providers without a monthly cap" do
    expect { described_class.spend!("balldontlie", 500, now: now) { } }.not_to raise_error
    expect(described_class.optional_allowed?("balldontlie", now: now)).to be(true)
  end
end
