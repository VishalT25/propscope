class DefenseRank < ApplicationRecord
  TIERS = %w[favorable neutral unfavorable].freeze

  belongs_to :team
  validates :tier, inclusion: { in: TIERS }
  validates :stat, :position, :season, :computed_at, presence: true
end
