class Market < ApplicationRecord
  GAME_TYPES = %w[moneyline spread total].freeze
  PLAYER_TYPES = %w[player_points player_rebounds player_assists player_threes player_pra].freeze

  belongs_to :game
  belongs_to :player, optional: true
  has_many :odds_snapshots, dependent: :destroy

  validates :market_type, inclusion: { in: GAME_TYPES + PLAYER_TYPES }
  validates :period, presence: true
  validate { errors.add(:player, "required for player markets") if market_type.in?(PLAYER_TYPES) && player.nil? }
  validate { errors.add(:line, "required unless moneyline") if market_type != "moneyline" && line.nil? }

  def player_prop? = market_type.in?(PLAYER_TYPES)
end
