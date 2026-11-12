# Where someone places their bets. Sportsbooks are licensed per province and per state: the same company runs a different site (and
# app listing) in each place, so a link that opens a slip has to point at the right one. Only the places we have a verified
# FanDuel address for are listed; add one here when it has been checked.
class Region < Data.define(:key, :name, :country, :fanduel_host)
  ALL = [
    new("on", "Ontario", "Canada", "on.sportsbook.fanduel.ca"),
    new("us", "United States", "United States", "sportsbook.fanduel.com")
  ].freeze

  DEFAULT_KEY = "us".freeze

  class << self
    def find(key) = ALL.find { |r| r.key == key.to_s }
    def default = find(DEFAULT_KEY)
    def keys = ALL.map(&:key)
  end

  def to_s = name
end
