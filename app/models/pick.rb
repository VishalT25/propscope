class Pick < ApplicationRecord
  belongs_to :user
  belongs_to :market
  belongs_to :bookmaker
  validates :side, :price_at_add, presence: true
end
