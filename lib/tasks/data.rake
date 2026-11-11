namespace :data do
  desc "Seed from fixtures (no API keys, no budget)"
  task seed_fixtures: :environment do
    Ingest::SeedFixtures.call
    puts "Seeded: #{Game.count} games, #{Player.count} players, #{PlayerGameLog.count} logs, #{OddsSnapshot.count} snapshots"
  end

  desc "Backfill schedule and box scores for N seasons (LIVE_DATA=true, SEASONS=2). Resumable: skips days already loaded. The same thing the setup page runs."
  task backfill_logs: :environment do
    abort "Set LIVE_DATA=true to call live APIs." unless LiveData.enabled?
    run = BackfillRun.create!(seasons: Integer(ENV.fetch("SEASONS", 2)))
    Backfill::Run.call(run, log: ->(message) { puts message })
    puts run.reload.done? ? "Done: #{PlayerGameLog.count} logs." : "#{run.state.capitalize}: #{run.message}"
    exit(1) unless run.done?
  end

  desc "Fetch odds now for the next 36 hours (LIVE_DATA=true). Use this in development, where the scheduler does not run."
  task refresh_odds: :environment do
    abort "Set LIVE_DATA=true to call live APIs." unless LiveData.enabled?
    before = BudgetGuard.report("sports_game_odds").used
    SnapshotOddsJob.perform_now("morning")
    after = BudgetGuard.report("sports_game_odds").used
    puts "Fetched odds: #{after - before} events used. Month so far: #{after}."
  end

  desc "Show API usage for the month and where it is heading"
  task quota: :environment do
    %w[sports_game_odds balldontlie].each do |provider|
      r = BudgetGuard.report(provider)
      cap = r.limit ? "#{r.used}/#{r.limit} (#{r.percent.round(1)}%), heading for ~#{r.projected}" : "#{r.used} requests (no monthly cap)"
      puts "#{provider.ljust(18)} #{cap}; #{r.days_left} days left"
    end
    puts "Extra pre-tip odds snapshots: ODDS_EXTRA_HOURS=#{SnapshotOddsJob.extra_hours} (0 to 6; optional ones stop at 80% of the budget)"
  end

  desc "Record a small real sample as fixtures (LIVE_DATA=true; spends budget). Review before committing."
  task capture_fixtures: :environment do
    abort "Set LIVE_DATA=true to call live APIs." unless LiveData.enabled?
    FixtureCapture.call
  end

  desc "Re-parse stored raw payloads without spending budget: PROVIDER=sports_game_odds SINCE=2026-11-01"
  task renormalize: :environment do
    provider = ENV.fetch("PROVIDER") { abort "PROVIDER=... required" }
    since = Time.zone.parse(ENV.fetch("SINCE", 14.days.ago.iso8601))
    puts "Re-normalized #{Ingest::Renormalizer.call(provider: provider, since: since)} payloads"
  end
end

namespace :model do
  desc "Write training rows for the model service: bin/rails model:export [OUT=tmp/model/points.csv]"
  task export: :environment do
    out = Rails.root.join(ENV.fetch("OUT", "tmp/model/points.csv"))
    FileUtils.mkdir_p(out.dirname)
    rows = ModelFeatures.new(stat: StatCatalog.for_market("player_points")).training_rows.sort_by(&:game_date)
    # Plain numbers and dates only (no commas or quotes), so no CSV library is needed. Blank = missing.
    File.open(out, "w") do |f|
      f.puts((%w[game_date player_id] + ModelFeatures::FEATURES + %w[target]).join(","))
      rows.each { |r| f.puts(([ r.game_date, r.player_id ] + ModelFeatures::FEATURES.map { |n| r.features[n] } + [ r.target ]).join(",")) }
    end
    puts "Wrote #{rows.size} rows to #{out}"
  end
end
