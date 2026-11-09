class PlayerGameLog < ApplicationRecord
  belongs_to :player
  belongs_to :game
  belongs_to :team
  belongs_to :opponent_team, class_name: "Team"

  validates :game_date, :season, presence: true

  scope :played, -> { where("minutes > 0") }   # DNP (0 minutes) games never count
  scope :recent_first, -> { order(game_date: :desc) }

  def dnp? = minutes.to_d.zero?
end
