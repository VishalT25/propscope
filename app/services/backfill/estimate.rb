module Backfill
  # How long loading history takes, before it starts. A season has about 165 game days; a day is about 4 pages of box scores.
  # The pace is the plan's: 60 requests a minute on BallDontLie's paid plan, 5 on the free one (which has no box scores).
  class Estimate
    GAME_DAYS_PER_SEASON = 165
    REQUESTS_PER_DAY = 4
    FIXED_REQUESTS = 12 # teams, players, the schedule

    Result = Data.define(:seasons, :game_days, :requests, :minutes)

    def self.call(seasons:, interval: Providers::Registry.min_interval("balldontlie"))
      days = seasons * GAME_DAYS_PER_SEASON
      requests = days * REQUESTS_PER_DAY + FIXED_REQUESTS
      Result.new(seasons, days, requests, (requests * interval.to_f / 60).ceil)
    end
  end
end
