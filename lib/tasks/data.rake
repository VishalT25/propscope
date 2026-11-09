namespace :data do
  desc "Seed from fixtures (no API keys, no budget)"
  task seed_fixtures: :environment do
    Ingest::SeedFixtures.call
    puts "Seeded: #{Game.count} games, #{Player.count} players, #{PlayerGameLog.count} logs, #{OddsSnapshot.count} snapshots"
  end

  desc "Backfill box scores for N seasons (LIVE_DATA=true, SEASONS=2). Slow on the free rate limit; resumable."
  task backfill_logs: :environment do
    abort "Set LIVE_DATA=true to call live APIs." unless LiveData.enabled?
    seasons = Integer(ENV.fetch("SEASONS", 2))
    provider = Providers::Registry.for(:stats)
    finish = Date.current - 1
    start = finish - (seasons * 365)
    (start..finish).each do |date|
      next if PlayerGameLog.exists?(game_date: date) # resumable: skip days already loaded
      result = Ingest::GameLogs.call(logs: provider.fetch_game_logs(sport: "nba", date: date))
      puts "#{date}: #{result.upserted} logs"
    rescue BudgetGuard::BudgetExceeded => e
      abort e.message
    end
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
