# Fully populated local app with no API keys: bin/rails db:seed (or bin/setup).
# Loads synthetic sample data through the same ingestion path as live data. Never seeds production.
Bookmaker::KNOWN.each do |key, (name, code)|
  Bookmaker.find_or_initialize_by(key: key).update!(name: name, code: code) # also refreshes older rows
end

if Rails.env.production?
  puts "Production: skipped sample data. Set LIVE_DATA=true and API keys to ingest real data."
else
  Ingest::SeedFixtures.call
  puts "Seeded #{Game.count} games, #{Player.count} players, #{PlayerGameLog.count} logs, #{OddsSnapshot.count} odds snapshots."
end

if Rails.env.development?
  User.find_or_create_by!(email_address: "admin@example.com") do |u|
    u.password = "password123"
    u.admin = true
  end
  puts "Dev admin: admin@example.com / password123"
end
