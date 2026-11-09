class Bookmaker < ApplicationRecord
  enum :kind, { sportsbook: "sportsbook", dfs: "dfs", exchange: "exchange", prediction: "prediction" }, default: :sportsbook

  validates :key, :name, :code, presence: true
  validates :key, uniqueness: true

  # The nine books on the SportsGameOdds free tier. Shown as text badges (code + name), never logos.
  KNOWN = {
    "draftkings" => [ "DraftKings", "DK" ], "fanduel" => [ "FanDuel", "FD" ], "betmgm" => [ "BetMGM", "MGM" ],
    "caesars" => [ "Caesars", "CZR" ], "espnbet" => [ "ESPN BET", "ESPN" ], "bovada" => [ "Bovada", "BOV" ],
    "unibet" => [ "Unibet", "UNI" ], "pointsbet" => [ "PointsBet", "PTS" ], "williamhill" => [ "William Hill", "WH" ]
  }.freeze

  # Providers report bookmakers by key; unknown ones are created on first sight.
  def self.for_key(key)
    find_by(key: key) || begin
      name, code = KNOWN.fetch(key.to_s) { [ key.to_s.titleize, key.to_s.upcase.first(3) ] }
      create!(key: key, name: name, code: code)
    end
  end
end
