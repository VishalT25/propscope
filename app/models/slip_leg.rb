class SlipLeg < ApplicationRecord
  RESULTS = %w[hit miss push void].freeze

  belongs_to :slip
  belongs_to :market
  belongs_to :bookmaker

  validates :side, inclusion: { in: %w[over under] }
  validates :result, inclusion: { in: RESULTS }, allow_nil: true

  scope :pending, -> { where(result: nil) }

  def pending? = result.nil?
end
