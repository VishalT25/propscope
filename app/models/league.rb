# Leagues shown in the sport chip row. Only enabled leagues have data (NBA first; see PROJECT_SPEC).
class League < Data.define(:key, :name, :enabled)
  ALL = [
    new("nba", "NBA", true),
    new("nfl", "NFL", false),
    new("nhl", "NHL", false),
    new("mlb", "MLB", false),
    new("wnba", "WNBA", false),
    new("ncaaf", "NCAAFB", false),
    new("ncaab", "NCAAMB", false),
    new("soccer", "Soccer", false)
  ].freeze

  class << self
    def find(key) = ALL.find { |l| l.key == key.to_s.downcase }
    def keys = ALL.map(&:key)
    def default = ALL.first
  end

  alias_method :enabled?, :enabled
  def to_param = key
end
