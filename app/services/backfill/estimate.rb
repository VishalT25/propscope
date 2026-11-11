module Backfill
  # How long loading history will take, before it starts. A full season has about 213 game days (regular season and playoffs, counted
  # from BallDontLie's schedule); the current season only counts the days played so far. A day is about 3 pages of box scores.
  # The pace is the plan's: 60 requests a minute on BallDontLie's paid plan, 5 on the free one (which has no box scores).
  class Estimate
    GAME_DAYS_PER_SEASON = 213
    SEASON_STARTS = [ 10, 22 ].freeze # month, day: about when the first games are played
    REQUESTS_PER_DAY = 3.2
    REFERENCE_FIXED = 7        # teams, plus the active-player pages
    REFERENCE_PER_SEASON = 9   # pages of games per season
    OVERHEAD = 1.15            # saving what arrives takes a little longer than the requests alone

    Result = Data.define(:seasons, :game_days, :requests, :minutes)

    def self.call(seasons:, interval: Providers::Registry.min_interval("balldontlie"), today: Date.current)
      days = game_days(seasons, today)
      requests = (days * REQUESTS_PER_DAY).ceil + reference_requests(seasons)
      Result.new(seasons, days, requests, (requests * interval.to_f * OVERHEAD / 60).ceil)
    end

    def self.reference_requests(seasons) = REFERENCE_FIXED + REFERENCE_PER_SEASON * seasons

    # Past seasons count in full; the current one only up to today.
    def self.game_days(seasons, today)
      current = today.month >= 10 ? today.year : today.year - 1
      played = (today - Date.new(current, *SEASON_STARTS)).to_i.clamp(0, GAME_DAYS_PER_SEASON)
      (seasons - 1) * GAME_DAYS_PER_SEASON + played
    end
  end
end
