class Team < ApplicationRecord
  belongs_to :sport
  has_many :players, dependent: :nullify
  has_one_attached :logo # an uploaded logo (see Images::Attach); logo_url points at it

  validates :abbreviation, :name, presence: true
  validates :abbreviation, uniqueness: { scope: :sport_id, case_sensitive: false }
end
