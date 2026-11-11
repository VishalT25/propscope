# A saved parlay. See Slips::Save (create), Slips::Grade (legs) and Slips::Settlement (overall result).
class Slip < ApplicationRecord
  belongs_to :user
  belongs_to :bookmaker, optional: true
  has_many :legs, -> { order(:id) }, class_name: "SlipLeg", dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :stake, numericality: { greater_than: 0 }
  validates :decimal_odds, numericality: { greater_than: 1 }
end
