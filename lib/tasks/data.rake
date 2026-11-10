namespace :data do
  desc "Seed from fixtures (no API keys, no budget)"
  task seed_fixtures: :environment do
    Ingest::SeedFixtures.call
    puts "Seeded: #{Game.count} games, #{Player.count} players, #{PlayerGameLog.count} logs, #{OddsSnapshot.count} snapshots"
  end

  desc "Backfill schedule and box scores for N seasons (LIVE_DATA=true, SEASONS=2). Resumable: skips days already loaded."
  task backfill_logs: :environment do
    abort "Set LIVE_DATA=true to call live APIs." unless LiveData.enabled?
    seasons = Integer(ENV.fetch("SEASONS", 2))
    provider = Providers::Registry.for(:stats)
    today = Date.current
    current_season = today.month >= 10 ? today.year : today.year - 1
    start = Date.new(current_season - seasons + 1, 10, 1)
    finish = today - 1

    puts "Syncing teams, players and the #{start}..#{today + 7} schedule"
    Ingest::ReferenceData.call(teams: provider.fetch_teams(sport: "nba"), players: provider.fetch_players(sport: "nba"))
    Ingest::ReferenceData.call(events: provider.fetch_events(sport: "nba", from: start, to: today + 7))

    days = Game.where(slate_date: start..finish).distinct.order(:slate_date).pluck(:slate_date) # only days that had games
    todo = days.reject { |d| PlayerGameLog.exists?(game_date: d) }
    puts "#{days.size} game days, #{todo.size} still to load"
    skipped = 0
    todo.each_with_index do |date, i|
      result = Ingest::GameLogs.call(logs: provider.fetch_game_logs(sport: "nba", date: date))
      skipped += result.skipped
      puts "[#{i + 1}/#{todo.size}] #{date}: #{result.upserted} logs (#{result.skipped} skipped)" if (i % 10).zero? || i == todo.size - 1
    rescue BudgetGuard::BudgetExceeded => e
      abort e.message
    end
    puts "Done: #{PlayerGameLog.count} logs, #{skipped} rows skipped (players no longer active are not in /players/active)"
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
    require "csv"
    out = Rails.root.join(ENV.fetch("OUT", "tmp/model/points.csv"))
    FileUtils.mkdir_p(out.dirname)
    rows = ModelFeatures.new(stat: StatCatalog.for_market("player_points")).training_rows.sort_by(&:game_date)
    CSV.open(out, "w") do |csv|
      csv << %w[game_date player_id] + ModelFeatures::FEATURES + %w[target]
      rows.each { |r| csv << [ r.game_date, r.player_id ] + ModelFeatures::FEATURES.map { |f| r.features[f] } + [ r.target ] }
    end
    puts "Wrote #{rows.size} rows to #{out}"
  end
end
