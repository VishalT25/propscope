# Maps prop market types to the box-score stat they are settled on.
module StatCatalog
  Stat = Data.define(:market_type, :defense_stat, :label, :short) do
    def value(log)
      case defense_stat
      when "points" then log.points
      when "rebounds" then log.rebounds
      when "assists" then log.assists
      when "threes_made" then log.threes_made
      when "pra" then log.points + log.rebounds + log.assists
      end
    end
  end

  ALL = [
    Stat.new("player_points", "points", "Points", "PTS"),
    Stat.new("player_rebounds", "rebounds", "Rebounds", "REB"),
    Stat.new("player_assists", "assists", "Assists", "AST"),
    Stat.new("player_threes", "threes_made", "3-Pointers Made", "3PM"),
    Stat.new("player_pra", "pra", "Pts + Reb + Ast", "PRA")
  ].freeze

  BY_MARKET = ALL.index_by(&:market_type).freeze
  DEFENSE_STATS = ALL.map(&:defense_stat).freeze

  def self.for_market(market_type) = BY_MARKET.fetch(market_type)

  # BallDontLie positions are G, F, C and hybrids like "G-F" / "F-C": bucket on the first token.
  def self.position_bucket(position) = position.to_s.split("-").first.presence
end
