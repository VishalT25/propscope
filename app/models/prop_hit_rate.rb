class PropHitRate < ApplicationRecord
  belongs_to :market
  validates :side, :computed_at, presence: true
end
