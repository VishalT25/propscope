#!/usr/bin/env ruby
# Generates SYNTHETIC sample fixtures in the documented BallDontLie / SportsGameOdds response shapes.
# Players are fictional; team names are real. Real captures (`bin/rails data:capture_fixtures`) replace these.
# Deterministic: same output every run. Anchor date is Providers::FixtureTransport::ANCHOR (2026-11-09).
#
#   ruby script/generate_sample_fixtures.rb
require "json"
require "date"
require "fileutils"

ANCHOR = Date.new(2026, 11, 9)
SEASON = 2026
ROOT = File.expand_path("../spec/fixtures/providers", __dir__)
RNG = Random.new(2026)

TEAMS = [
  [ 1, "ATL", "Atlanta", "Hawks", "East", "Southeast" ], [ 2, "BOS", "Boston", "Celtics", "East", "Atlantic" ],
  [ 3, "BKN", "Brooklyn", "Nets", "East", "Atlantic" ], [ 4, "CHA", "Charlotte", "Hornets", "East", "Southeast" ],
  [ 5, "CHI", "Chicago", "Bulls", "East", "Central" ], [ 6, "CLE", "Cleveland", "Cavaliers", "East", "Central" ],
  [ 7, "DAL", "Dallas", "Mavericks", "West", "Southwest" ], [ 8, "DEN", "Denver", "Nuggets", "West", "Northwest" ],
  [ 9, "DET", "Detroit", "Pistons", "East", "Central" ], [ 10, "GSW", "Golden State", "Warriors", "West", "Pacific" ],
  [ 11, "HOU", "Houston", "Rockets", "West", "Southwest" ], [ 12, "LAL", "Los Angeles", "Lakers", "West", "Pacific" ],
  [ 13, "MIA", "Miami", "Heat", "East", "Southeast" ], [ 14, "MIL", "Milwaukee", "Bucks", "East", "Central" ],
  [ 15, "NYK", "New York", "Knicks", "East", "Atlantic" ], [ 16, "PHX", "Phoenix", "Suns", "West", "Pacific" ]
].freeze

FIRST = %w[Marcus Darius Tyrese Jalen Andre Cole Devin Isaiah Malik Quentin Rashad Terrell Xavier Zane Elias Owen Silas Rowan Callum Dario].freeze
LAST = %w[Vale Holloway Brightwater Okonkwo-Reyes Stanton Merrick Ashby Calloway Whitlock Fairbanks Sandoval Kingsley Thornton Abernathy
          Delacroix Pemberton Ravenscroft Lockhart Ellison Winthrop Harlan Montrose Prescott Quimby Redfield Sutherland Tillman Vance Wexler Yarbrough].freeze
POSITIONS = %w[G G-F F F-C C G].freeze

# Hand-picked tricky names (accents, suffixes, hyphens, nicknames): [first, last, sgo_name]
SPECIAL = {
  0 => [ "Dušan", "Marković", "Dusan Markovic" ],
  1 => [ "Jaylen", "Brooks Jr.", "Jaylen Brooks" ],
  2 => [ "Tyrese", "Gilmore-Adeyemi", "Tyrese Gilmore Adeyemi" ],
  3 => [ "Nikolas", "Petrović III", "Nikolas Petrovic" ],
  4 => [ "Michael", "Stanhope", "Mike Stanhope" ]
}.freeze

def gauss(mean, sd)
  u1 = [ RNG.rand, 1e-9 ].max
  u2 = RNG.rand
  mean + sd * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
end

def slug(str) = str.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/\A_|_\z/, "")

teams = TEAMS.map { |id, abbr, city, name, conf, div| { id: id, abbr: abbr, city: city, name: name, conf: conf, div: div, full: "#{city} #{name}" } }

# 6 players per team: [slot 0..5]; slots 0-4 starters-ish. Ratings drive logs and prop lines.
players = []
pid = 100
teams.each_with_index do |team, ti|
  6.times do |slot|
    special = SPECIAL[(ti + slot * 3) % 16] if slot < 5 && ti < 5
    first, last, sgo_name = special || [ FIRST[(ti * 6 + slot) % FIRST.size], LAST[(ti * 6 + slot * 5 + 3) % LAST.size], nil ]
    sgo_name ||= "#{first} #{last}"
    minutes = [ 34, 32, 30, 27, 22, 16 ][slot] + RNG.rand(-2..2)
    usage = 0.45 + RNG.rand * 0.35
    players << {
      id: pid += 1, team: team, first: first, last: last, sgo_name: sgo_name, position: POSITIONS[slot], slot: slot,
      minutes: minutes, pts: minutes * usage, reb: minutes * (0.12 + RNG.rand * 0.18), ast: minutes * (0.06 + RNG.rand * 0.2),
      fg3: minutes * (0.03 + RNG.rand * 0.07)
    }
  end
end
roster = players.group_by { |p| p[:team][:id] }

# Schedule: ~6-8 games a day for the 31 days before the anchor, then the 8-game slate on the anchor day.
games = []
gid = 5000
(-31..-1).each do |offset|
  date = ANCHOR + offset
  pool = teams.shuffle(random: RNG)
  RNG.rand(5..8).times do |i|
    home, away = pool[i * 2], pool[i * 2 + 1]
    games << { id: gid += 1, date: date, home: home, away: away, final: true }
  end
end
slate_pool = teams.shuffle(random: Random.new(7))
8.times { |i| games << { id: gid += 1, date: ANCHOR, home: slate_pool[i * 2], away: slate_pool[i * 2 + 1], final: false, slot: i } }

def team_json(t) = { id: t[:id], conference: t[:conf], division: t[:div], city: t[:city], name: t[:name], full_name: t[:full], abbreviation: t[:abbr] }

TIMES = %w[23:00 23:30 00:00 00:00 00:30 01:00 02:00 02:30].freeze # UTC; evening ET

stats = []
games_json = games.map do |g|
  start_time = g[:final] ? "00:00" : TIMES[g[:slot]]
  start_date = start_time < "12:00" ? g[:date] + 1 : g[:date]
  datetime = "#{start_date}T#{start_time}:00.000Z"
  home_score = away_score = nil
  if g[:final]
    totals = { g[:home][:id] => 0, g[:away][:id] => 0 }
    [ g[:home], g[:away] ].each do |team|
      roster[team[:id]].each do |p|
        dnp = RNG.rand < 0.04
        mins = dnp ? 0 : [ gauss(p[:minutes], 4), 4 ].max
        scale = mins / p[:minutes]
        pts = dnp ? 0 : [ gauss(p[:pts] * scale, 5.5).round, 0 ].max
        totals[team[:id]] += pts
        sec = ((mins % 1) * 60).round
        stats << {
          id: stats.size + 1, min: dnp ? "" : format("%d:%02d", mins.floor, sec),
          fgm: (pts / 2.3).round, fga: (pts / 1.1).round, fg3m: dnp ? 0 : [ gauss(p[:fg3] * scale, 1.1).round, 0 ].max, fg3a: (p[:fg3] * 2.4).round,
          ftm: (pts / 6.0).round, fta: (pts / 5.0).round, oreb: dnp ? 0 : [ gauss(p[:reb] * 0.25, 0.9).round, 0 ].max,
          dreb: dnp ? 0 : [ gauss(p[:reb] * 0.75 * scale, 1.8).round, 0 ].max,
          reb: 0, ast: dnp ? 0 : [ gauss(p[:ast] * scale, 2.0).round, 0 ].max, stl: dnp ? 0 : [ gauss(1.0, 0.9).round, 0 ].max,
          blk: dnp ? 0 : [ gauss(0.6, 0.8).round, 0 ].max, turnover: dnp ? 0 : [ gauss(1.9, 1.3).round, 0 ].max,
          pf: dnp ? 0 : [ gauss(2.2, 1.2).round, 0 ].max, pts: pts, plus_minus: dnp ? 0 : RNG.rand(-12..12),
          player: { id: p[:id], first_name: p[:first], last_name: p[:last], position: p[:position], team_id: team[:id] },
          team: { id: team[:id] },
          game: { id: g[:id], date: g[:date].to_s, season: SEASON, home_team_id: g[:home][:id], visitor_team_id: g[:away][:id] }
        }.tap { |s| s[:reb] = s[:oreb] + s[:dreb] }
      end
    end
    home_score, away_score = totals[g[:home][:id]], totals[g[:away][:id]]
  end
  {
    id: g[:id], date: g[:date].to_s, season: SEASON, status: g[:final] ? "Final" : datetime, period: g[:final] ? 4 : 0, time: g[:final] ? "Final" : "",
    postseason: false, postponed: false, home_team_score: home_score, visitor_team_score: away_score, datetime: datetime,
    home_team: team_json(g[:home]), visitor_team: team_json(g[:away])
  }
end

FileUtils.mkdir_p("#{ROOT}/balldontlie")
FileUtils.mkdir_p("#{ROOT}/sports_game_odds")
write = ->(path, body) { File.write("#{ROOT}/#{path}.json", JSON.generate(body)) }
write.("balldontlie/teams", { data: teams.map { |t| team_json(t) } })
write.("balldontlie/players_active", {
  data: players.map { |p| { id: p[:id], first_name: p[:first], last_name: p[:last], position: p[:position], height: nil, weight: nil, jersey_number: (p[:slot] + 1).to_s, college: nil, country: nil, team: team_json(p[:team]) } },
  meta: { per_page: 100 }
})
write.("balldontlie/games", { data: games_json, meta: { per_page: 100 } })
write.("balldontlie/stats", { data: stats, meta: { per_page: 100 } })

# ---- SportsGameOdds-shaped events for the anchor-day slate ----
BOOKS = %w[draftkings fanduel betmgm caesars espnbet].freeze
STATS = { "points" => :pts, "rebounds" => :reb, "assists" => :ast, "threePointersMade" => :fg3, "points+rebounds+assists" => :pra }.freeze

def american(imp)
  imp = imp.clamp(0.05, 0.95)
  imp >= 0.5 ? -(imp / (1 - imp) * 100).round : ((1 - imp) / imp * 100).round
end

events = games.reject { |g| g[:final] }.map do |g|
  home, away = g[:home], g[:away]
  start_time = TIMES[g[:slot]]
  start_date = start_time < "12:00" ? g[:date] + 1 : g[:date]
  odds = {}
  home_win = (0.5 + RNG.rand * 0.3 - 0.15).round(3)
  spread = ((0.5 - home_win) * 30).round * 1.0 - 0.5 # home spread, e.g. -3.5
  total = 215.5 + RNG.rand(0..16)
  add = lambda do |odd_id, entries|
    odds[odd_id] = { oddID: odd_id, byBookmaker: entries }
  end
  mk = ->(prob) { BOOKS.each_with_index.to_h { |b, i| [ b, { odds: american(prob + (RNG.rand - 0.5) * 0.03 + (i - 2) * 0.004 + 0.023).to_s, available: true } ] } }
  add.("points-home-game-ml-home", mk.(home_win))
  add.("points-away-game-ml-away", mk.(1 - home_win))
  with_line = lambda do |prob, key, line_for|
    BOOKS.each_with_index.to_h do |b, i|
      [ b, { odds: american(prob + (RNG.rand - 0.5) * 0.03 + 0.0225).to_s, key => format("%.1f", line_for.(i)), available: true } ]
    end
  end
  add.("points-home-game-sp-home", with_line.(0.5, :spread, ->(i) { spread + (i == 3 ? 0.5 : 0) }))
  add.("points-away-game-sp-away", with_line.(0.5, :spread, ->(i) { -spread - (i == 3 ? 0.5 : 0) }))
  add.("points-all-game-ou-over", with_line.(0.5, :overUnder, ->(_i) { total }))
  add.("points-all-game-ou-under", with_line.(0.5, :overUnder, ->(_i) { total }))
  add.("points-home-1h-ml-home", mk.(home_win)) # period markets are out of scope; parser must ignore

  event_players = {}
  [ home, away ].each do |team|
    roster[team[:id]].first(4).each do |p|
      pid_sgo = "#{slug(p[:sgo_name])}_1_NBA"
      event_players[pid_sgo] = { playerID: pid_sgo, teamID: "#{slug(team[:full])}_NBA", firstName: p[:sgo_name].split.first, lastName: p[:sgo_name].split[1..].join(" "), name: p[:sgo_name] }
      STATS.each do |stat, key|
        mean = key == :pra ? p[:pts] + p[:reb] + p[:ast] : p[key]
        base_line = ((mean * 2).round / 2.0) - 0.5 + (RNG.rand < 0.5 ? 0 : 1)
        base_line = [ base_line, 0.5 ].max
        over = {}
        under = {}
        BOOKS.each_with_index do |b, i|
          line = format("%.1f", base_line + ((i == 3 && RNG.rand < 0.5) ? 0.5 : 0))
          fair_over = 0.5 + (RNG.rand - 0.5) * 0.08
          over[b] = { odds: american(fair_over + 0.0225).to_s, overUnder: line, available: true }
          under[b] = { odds: american(1 - fair_over + 0.0225).to_s, overUnder: line, available: true }
        end
        add.("#{stat}-#{pid_sgo}-game-ou-over", over)
        add.("#{stat}-#{pid_sgo}-game-ou-under", under)
      end
    end
  end

  # one deliberately unmatched player to exercise the unresolved-entities path
  if g[:slot] == 0
    event_players["UNMATCHED_ROOKIE_1_NBA"] = { playerID: "UNMATCHED_ROOKIE_1_NBA", teamID: "#{slug(home[:full])}_NBA", name: "Unmatched Rookie", firstName: "Unmatched", lastName: "Rookie" }
    add.("points-UNMATCHED_ROOKIE_1_NBA-game-ou-over", { "draftkings" => { odds: "-115", overUnder: "9.5", available: true } })
    add.("points-UNMATCHED_ROOKIE_1_NBA-game-ou-under", { "draftkings" => { odds: "-105", overUnder: "9.5", available: true } })
  end

  {
    eventID: "EVT_#{home[:abbr]}_#{away[:abbr]}_#{g[:date].strftime('%Y%m%d')}", sportID: "BASKETBALL", leagueID: "NBA", type: "match",
    teams: {
      home: { teamID: "#{slug(home[:full])}_NBA", names: { long: home[:full], medium: home[:name], short: home[:abbr] } },
      away: { teamID: "#{slug(away[:full])}_NBA", names: { long: away[:full], medium: away[:name], short: away[:abbr] } }
    },
    status: { startsAt: "#{start_date}T#{start_time}:00.000Z", started: false, ended: false, oddsAvailable: true },
    players: event_players, odds: odds
  }
end
write.("sports_game_odds/events", { success: true, data: events })

puts "teams=#{teams.size} players=#{players.size} games=#{games.size} stat_rows=#{stats.size} events=#{events.size}"
Dir["#{ROOT}/*/*.json"].sort.each { |f| puts format("%-60s %6d KB", f.sub(ROOT + "/", ""), File.size(f) / 1024) }
