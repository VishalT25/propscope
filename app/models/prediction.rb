# Output of the optional Python model service. Nothing in the app depends on these rows existing.
class Prediction < ApplicationRecord
  belongs_to :market
  validates :side, inclusion: { in: %w[over under] }
  validates :probability, :model_version, :computed_at, presence: true
  validates :probability, numericality: { greater_than: 0, less_than: 1 }
end
