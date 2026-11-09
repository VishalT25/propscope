module Dto
  # A scheduled/finished game. status: scheduled | in_progress | final | postponed
  Event = Data.define(:provider, :external_id, :home_team, :away_team, :starts_at, :status, :home_score, :away_score, :season)
end
