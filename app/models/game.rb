class Game < ApplicationRecord
  SLATE_ZONE = "America/New_York".freeze

  belongs_to :sport
  belongs_to :home_team, class_name: "Team"
  belongs_to :away_team, class_name: "Team"
  has_many :markets, dependent: :destroy
  has_many :game_logs, class_name: "PlayerGameLog", dependent: :destroy

  enum :status, { scheduled: "scheduled", in_progress: "in_progress", final: "final", postponed: "postponed" }, default: :scheduled

  before_validation { self.slate_date = starts_at.in_time_zone(SLATE_ZONE).to_date if starts_at }

  validates :starts_at, :season, presence: true
  validate { errors.add(:away_team, "must differ from home team") if home_team_id && home_team_id == away_team_id }

  scope :upcoming, ->(within: 36.hours, now: Time.current) { where(starts_at: now..now + within).order(:starts_at) }

  def teams = [ home_team, away_team ]
  def opponent_of(team) = team == home_team ? away_team : home_team
end
