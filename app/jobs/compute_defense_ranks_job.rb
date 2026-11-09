# Defence vs position ranks from our own logs. Nightly after stats ingest.
class ComputeDefenseRanksJob < ApplicationJob
  queue_as :default

  def perform
    season = Game.where("starts_at >= ?", Time.current).order(:starts_at).pick(:season) || Game.maximum(:season) or return
    DefenseRanker.call(season: season)
  end
end
